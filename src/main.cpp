// esca-voiceapp: a button, a waveform, and what was heard.
//
// Press to talk. The button does not become a waveform until esca-voiced
// says it is genuinely ready -- the microphone open and the server
// answering -- so nobody is invited to speak into something that is not
// listening. That handshake is the reason the service has a "preparing"
// state at all.
//
// The lower half speaks: type nothing, press Say, and the last transcript
// is read back through the speaker. It is the shortest honest test of the
// whole round trip, and it exercises text to speech without a keyboard.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdio>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

#include "esca/ui/render.hpp"
#include "esca/ui/window.hpp"

using namespace esca::ui;

namespace {

constexpr const char *kVoiceService = "vn.sparc.esca.Voice1";
constexpr const char *kVoicePath = "/vn/sparc/esca/Voice1";
constexpr const char *kVoiceInterface = "vn.sparc.esca.Voice1";

volatile std::sig_atomic_t g_quit = 0;
void handle_signal(int) { g_quit = 1; }

constexpr uint32_t kBackground = 0xff101418;
constexpr uint32_t kPanel = 0xff1b2128;
constexpr uint32_t kText = 0xffe8eaed;
constexpr uint32_t kDim = 0xff8a929b;
constexpr uint32_t kAccent = 0xff4fc3f7;
constexpr uint32_t kBusy = 0xffffb74d;
constexpr uint32_t kBad = 0xffe57373;
constexpr uint32_t kGood = 0xffaed581;

/// Everything the bus thread writes and the drawing thread reads.
struct Shared {
    std::mutex mutex;
    std::string phase = "idle";
    std::string transcript;
    std::string language;
    std::string error;
    double confidence = 0.0;
    double ms = 0.0;
    double level_db = -90.0;
    double floor_db = -90.0;
    bool speaking = false;
    /// Recent levels, newest last. Only as many as the waveform draws.
    std::deque<double> history;
};

void push_level(Shared &shared, double db, size_t keep)
{
    shared.history.push_back(db);
    while (shared.history.size() > keep)
        shared.history.pop_front();
}

/// A filled rectangle with a label centred in it.
void draw_button(uint32_t *px, int w, int h, int stride, const Rect &r,
                 const std::string &label, uint32_t fill, uint32_t ink, int scale)
{
    fill_rect(px, w, h, stride, r, fill);
    stroke_rect(px, w, h, stride, r, ink, 2);
    const int tw = text_width(label, scale);
    const int th = text_height(scale);
    draw_text(px, w, h, stride, r.x + (r.w - tw) / 2, r.y + (r.h - th) / 2, label, ink,
              scale);
}

/// Word-wrapped text, because a transcript is a sentence and the screen is
/// not as wide as one.
int draw_wrapped(uint32_t *px, int w, int h, int stride, int x, int y, int max_width,
                 const std::string &text, uint32_t colour, int scale)
{
    const int line_height = text_height(scale) + scale * 3;
    std::string line;
    int lines = 0;

    auto flush = [&] {
        if (line.empty())
            return;
        draw_text(px, w, h, stride, x, y + lines * line_height, line, colour, scale);
        ++lines;
        line.clear();
    };

    size_t start = 0;
    while (start <= text.size()) {
        const size_t space = text.find(' ', start);
        const std::string word =
            text.substr(start, space == std::string::npos ? std::string::npos : space - start);

        const std::string candidate = line.empty() ? word : line + " " + word;
        if (text_width(candidate, scale) > max_width && !line.empty())
            flush();
        line = line.empty() ? word : line + " " + word;

        if (space == std::string::npos)
            break;
        start = space + 1;
    }
    flush();
    return lines * line_height;
}

} // namespace

int main(int argc, char **argv)
{
    std::string error;
    int scale = 3;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--scale" && i + 1 < argc)
            scale = std::stoi(argv[++i]);
        else {
            std::fprintf(stderr, "usage: esca-voiceapp [--scale N]\n");
            return 2;
        }
    }

    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    Shared shared;

    // The proxy runs its own bus thread, so the drawing loop never pumps
    // D-Bus; it just reads the latest state under the mutex before drawing.
    auto proxy = sdbus::createProxy(sdbus::createSystemBusConnection(),
                                    sdbus::ServiceName { kVoiceService },
                                    sdbus::ObjectPath { kVoicePath });

    proxy->uponSignal("StateChanged").onInterface(kVoiceInterface).call([&](const std::string &p) {
        std::lock_guard<std::mutex> lock(shared.mutex);
        shared.phase = p;
        if (p == "listening") {
            shared.history.clear();
            shared.error.clear();
        }
    });
    proxy->uponSignal("Level").onInterface(kVoiceInterface).call([&](const double &db,
                                                                    const double &floor) {
        std::lock_guard<std::mutex> lock(shared.mutex);
        shared.level_db = db;
        shared.floor_db = floor;
        push_level(shared, db, 256);
    });
    proxy->uponSignal("SpeechStarted").onInterface(kVoiceInterface).call([&](const uint64_t &) {
        std::lock_guard<std::mutex> lock(shared.mutex);
        shared.speaking = true;
    });
    proxy->uponSignal("SpeechEnded")
        .onInterface(kVoiceInterface)
        .call([&](const uint64_t &, const double &) {
            std::lock_guard<std::mutex> lock(shared.mutex);
            shared.speaking = false;
        });
    proxy->uponSignal("Transcript")
        .onInterface(kVoiceInterface)
        .call([&](const uint64_t &, const std::string &text, const std::string &language,
                  const double &confidence, const double &ms) {
            std::lock_guard<std::mutex> lock(shared.mutex);
            shared.transcript = text.empty() ? "(nothing heard)" : text;
            shared.language = language;
            shared.confidence = confidence;
            shared.ms = ms;
        });
    proxy->uponSignal("FaultEvent")
        .onInterface(kVoiceInterface)
        .call([&](const std::string &where, const std::string &what) {
            std::lock_guard<std::mutex> lock(shared.mutex);
            shared.error = where + ": " + what;
        });

    Window window;
    if (!window.open("ESCA Voice", "vn.sparc.esca.voiceapp", error)) {
        std::fprintf(stderr, "esca-voiceapp: %s\n", error.c_str());
        return 1;
    }

    while (!g_quit && !window.closed()) {
        if (!window.dispatch()) {
            std::fprintf(stderr, "esca-voiceapp: compositor went away\n");
            break;
        }

        int w = 0, h = 0, stride = 0;
        uint32_t *px = window.acquire(w, h, stride);
        if (!px) {
            // Both buffers are with the compositor. Nothing here is
            // time-critical, so wait for the next turn rather than spin.
            continue;
        }

        std::string phase, transcript, language, fault;
        double confidence = 0, ms = 0, level = -90, floor = -90;
        bool speaking = false;
        std::vector<double> history;
        {
            std::lock_guard<std::mutex> lock(shared.mutex);
            phase = shared.phase;
            transcript = shared.transcript;
            language = shared.language;
            fault = shared.error;
            confidence = shared.confidence;
            ms = shared.ms;
            level = shared.level_db;
            floor = shared.floor_db;
            speaking = shared.speaking;
            history.assign(shared.history.begin(), shared.history.end());
        }

        fill_rect(px, w, h, stride, { 0, 0, w, h }, kBackground);

        const int margin = 24 * scale / 3;
        const int title = text_height(scale) + margin;
        draw_text(px, w, h, stride, margin, margin / 2, "ESCA Voice", kDim, scale);

        // --- the button, or the waveform it becomes ------------------------
        const Rect stage { margin, title, w - 2 * margin, h / 2 - title };

        const bool listening = phase == "listening";
        const bool preparing = phase == "preparing";
        const bool transcribing = phase == "transcribing";

        if (listening) {
            fill_rect(px, w, h, stride, stage, kPanel);

            // The waveform. Levels run from the noise floor the service is
            // tracking up to 0 dBFS, so a loud room does not peg it full.
            const double top = 0.0;
            const double bottom = std::min(floor - 6.0, -60.0);
            const int mid = stage.y + stage.h / 2;
            const int bars = std::min<int>(history.size(), stage.w / (2 * scale));

            for (int i = 0; i < bars; ++i) {
                const double db = history[history.size() - bars + i];
                const double t = std::clamp((db - bottom) / (top - bottom), 0.0, 1.0);
                const int half = std::max(1, static_cast<int>(t * (stage.h / 2 - 8)));
                const int x = stage.x + 4 + i * 2 * scale;
                fill_rect(px, w, h, stride, { x, mid - half, scale, half * 2 },
                          db > floor + 9.0 ? kAccent : kDim);
            }

            const std::string hint = speaking ? "listening..." : "speak now";
            draw_text(px, w, h, stride, stage.x + 8, stage.y + 8, hint,
                      speaking ? kAccent : kDim, scale);
        } else {
            const uint32_t fill = preparing || transcribing ? kPanel : kPanel;
            const uint32_t ink = preparing   ? kBusy
                                 : transcribing ? kBusy
                                                : kAccent;
            const std::string label = preparing      ? "PREPARING..."
                                      : transcribing ? "TRANSCRIBING..."
                                                     : "PRESS TO TALK";
            draw_button(px, w, h, stride, stage, label, fill, ink, scale + 1);
        }

        // --- what was heard -------------------------------------------------
        int y = h / 2 + margin / 2;
        draw_text(px, w, h, stride, margin, y, "HEARD", kDim, scale - 1);
        y += text_height(scale - 1) + margin / 2;

        if (!transcript.empty()) {
            y += draw_wrapped(px, w, h, stride, margin, y, w - 2 * margin, transcript, kText,
                              scale);
            char detail[128];
            std::snprintf(detail, sizeof(detail), "%s  %.0f%% confident  %.0f ms",
                          language.c_str(), confidence * 100.0, ms);
            draw_text(px, w, h, stride, margin, y + margin / 2, detail, kDim, scale - 1);
        } else {
            draw_text(px, w, h, stride, margin, y, "nothing yet", kDim, scale);
        }

        // --- say it back ----------------------------------------------------
        const int button_h = text_height(scale) + margin;
        const Rect say { margin, h - button_h - margin, (w - 3 * margin) / 2, button_h };
        const Rect stop { say.x + say.w + margin, say.y, say.w, button_h };
        draw_button(px, w, h, stride, say, "SAY IT BACK", kPanel,
                    transcript.empty() ? kDim : kGood, scale);
        draw_button(px, w, h, stride, stop, "STOP", kPanel, kDim, scale);

        if (!fault.empty()) {
            draw_text(px, w, h, stride, margin, say.y - text_height(scale - 1) - 4, fault,
                      kBad, scale - 1);
        }

        // --- input ----------------------------------------------------------
        const Input in = window.take_input();
        if (in.clicked) {
            try {
                if (Window::hit(in, stage.x, stage.y, stage.w, stage.h) && phase == "idle") {
                    int32_t rc = 0;
                    proxy->callMethod("StartListening")
                        .onInterface(kVoiceInterface)
                        .storeResultsTo(rc);
                } else if (Window::hit(in, say.x, say.y, say.w, say.h) && !transcript.empty()) {
                    int32_t token = 0;
                    proxy->callMethod("Say")
                        .onInterface(kVoiceInterface)
                        .withArguments(transcript)
                        .storeResultsTo(token);
                } else if (Window::hit(in, stop.x, stop.y, stop.w, stop.h)) {
                    int32_t rc = 0;
                    proxy->callMethod("StopListening")
                        .onInterface(kVoiceInterface)
                        .storeResultsTo(rc);
                }
            } catch (const sdbus::Error &e) {
                std::lock_guard<std::mutex> lock(shared.mutex);
                shared.error = e.getMessage();
            }
        }

        window.present();

        // 30 Hz is plenty for a waveform fed at 20 Hz, and leaves the core
        // to whatever is listening.
        std::this_thread::sleep_for(std::chrono::milliseconds(33));
    }

    window.close();
    return 0;
}
