#pragma once

#include <algorithm>
#include <cctype>
#include <iomanip>
#include <numeric>
#include <sstream>
#include <string>
#include <unordered_set>
#include <vector>
#include <nlohmann/json.hpp>

struct Record {
  int id, score;
  std::string service, level, message;
};

class Workspace {
 public:
  explicit Workspace(const nlohmann::json& spec)
      : width_(spec.at("width")), page_(spec.at("height").get<int>() - 8) {
    for (const auto& row : spec.at("records")) {
      records_.push_back({row.at("id"), row.at("score"), row.at("service"), row.at("level"), row.at("message")});
    }
    matches_.resize(records_.size());
    std::iota(matches_.begin(), matches_.end(), 0);
  }

  bool Apply(char key) {
    static const std::string keys = "jkpgGxfesa";
    static const std::vector<std::string> labels = {"down","up","page","home","end","select","search","errors","sort","append"};
    const auto position = keys.find(key);
    if (position == std::string::npos) return false;
    ++step_;
    switch (key) {
      case 'j': ++cursor_; break;
      case 'k': --cursor_; break;
      case 'p': cursor_ += page_; break;
      case 'g': cursor_ = 0; break;
      case 'G': cursor_ = static_cast<int>(matches_.size()) - 1; break;
      case 'x': if (!matches_.empty()) {
        const auto id = records_[matches_[cursor_]].id;
        if (!selected_.erase(id)) selected_.insert(id);
      } break;
      case 'f': query_ = query_.empty() ? "needle" : ""; Rebuild(); break;
      case 'e': errors_ = !errors_; Rebuild(); break;
      case 's': order_ = order_ == "score-desc" ? "score-asc" : "score-desc"; Rebuild(); break;
      case 'a': {
        const int id = static_cast<int>(records_.size());
        const std::vector<std::string> levels = {"INFO", "WARN", "ERROR", "DEBUG"};
        records_.push_back({id, id * 37 % 10000, "service-" + Pad(id % 17, 2), levels[id % 4],
          "request " + Pad(id, 6) + (id % 97 == 0 ? " needle" : " regular")});
        Rebuild(); break;
      }
    }
    cursor_ = std::max(0, std::min(cursor_, static_cast<int>(matches_.size()) - 1));
    if (cursor_ < top_) top_ = cursor_;
    if (cursor_ >= top_ + page_) top_ = cursor_ - page_ + 1;
    logs_.push_back(Pad(step_,6) + " " + labels[position] + " cursor=" + std::to_string(cursor_) + " matches=" + std::to_string(matches_.size()));
    if (logs_.size() > 3) logs_.erase(logs_.begin());
    return true;
  }

  std::vector<std::string> Lines() const {
    std::vector<std::string> lines = {
      "Workspace step=" + Pad(step_,6) + " rows=" + std::to_string(records_.size()) + " matches=" + std::to_string(matches_.size()) + " selected=" + std::to_string(selected_.size()),
      "query=" + (query_.empty() ? "-" : query_) + " errors=" + std::to_string(errors_) + " sort=" + order_ + " cursor=" + std::to_string(cursor_) + " top=" + std::to_string(top_),
      "   ID     SERVICE    LEVEL SCORE MESSAGE"};
    for (int index = top_; index < top_ + page_; ++index) {
      if (index >= static_cast<int>(matches_.size())) { lines.emplace_back(); continue; }
      const auto& row = records_[matches_[index]];
      std::ostringstream line;
      line << (index == cursor_ ? '>' : ' ') << (selected_.count(row.id) ? '*' : ' ') << ' '
        << Pad(row.id,6) << ' ' << row.service << ' ' << std::left << std::setw(5) << row.level
        << ' ' << Pad(row.score,4) << ' ' << row.message;
      lines.push_back(line.str());
    }
    lines.push_back("Event log");
    for (auto index = logs_.size(); index < 3; ++index) lines.emplace_back();
    lines.insert(lines.end(), logs_.begin(), logs_.end());
    lines.push_back("j/k move  p page  g/G home/end  x select  f search  e errors  s sort  a append  q quit");
    for (auto& line : lines) { line.resize(width_, ' '); }
    return lines;
  }

 private:
  static std::string Pad(int value, int width) {
    std::ostringstream text;
    text << std::setw(width) << std::setfill('0') << value;
    return text.str();
  }
  void Rebuild() {
    matches_.clear();
    for (int index = 0; index < static_cast<int>(records_.size()); ++index) {
      const auto& row = records_[index];
      auto haystack = row.service + " " + row.level + " " + row.message;
      std::transform(haystack.begin(), haystack.end(), haystack.begin(), [](unsigned char c) { return std::tolower(c); });
      if ((!errors_ || row.level == "ERROR") && haystack.find(query_) != std::string::npos) matches_.push_back(index);
    }
    if (order_ != "id") std::sort(matches_.begin(), matches_.end(), [&](int a, int b) {
      const auto& left = records_[a]; const auto& right = records_[b];
      if (left.score == right.score) return left.id < right.id;
      return order_ == "score-desc" ? left.score > right.score : left.score < right.score;
    });
    cursor_ = top_ = 0;
  }
  int width_, page_, cursor_ = 0, top_ = 0, step_ = 0;
  bool errors_ = false;
  std::string query_, order_ = "id";
  std::vector<Record> records_;
  std::vector<int> matches_;
  std::unordered_set<int> selected_;
  std::vector<std::string> logs_ = {"ready"};
};
