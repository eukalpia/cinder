#include "workspace.hpp"

#include <chrono>
#include <fstream>
#include <memory>
#include <thread>
#include <ftxui/component/component.hpp>
#include <ftxui/component/event.hpp>
#include <ftxui/component/screen_interactive.hpp>
#include <ftxui/dom/elements.hpp>

int main(int argc, char** argv) {
  if (argc != 2) return 64;
  std::ifstream input(argv[1]);
  const auto spec = nlohmann::json::parse(input);
  auto model = spec.value("kind", "") == "workspace-v1" ? std::make_unique<Workspace>(spec) : nullptr;
  auto screen = ftxui::ScreenInteractive::Fullscreen();
  screen.TrackMouse(false);
  int counter = 0;
  auto next_frame = std::chrono::steady_clock::now();
  auto interval = std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(1.0 / spec.at("fps").get<double>()));
  auto renderer = ftxui::Renderer([&] {
    // FTXUI owns input and output. Its public Renderer callback is rate-limited
    // by the application because FTXUI exposes no general input FPS setting.
    std::this_thread::sleep_until(next_frame);
    next_frame = std::chrono::steady_clock::now() + interval;
    std::vector<std::string> lines;
    if (model) lines = model->Lines();
    else {
      std::istringstream source(spec.at("frames").at(counter % 2).get<std::string>());
      for (std::string line; std::getline(source,line);) lines.push_back(line);
    }
    ftxui::Elements elements;
    for (const auto& line : lines) elements.push_back(ftxui::text(line));
    return ftxui::vbox(std::move(elements));
  });
  auto application = ftxui::CatchEvent(renderer, [&](ftxui::Event event) {
    if (event == ftxui::Event::Character('q')) { screen.Exit(); return true; }
    if (!event.is_character() || event.character().size() != 1) return false;
    if (model) return model->Apply(event.character()[0]);
    if (event == ftxui::Event::Character('n')) { ++counter; return true; }
    return false;
  });
  screen.Loop(application);
}
