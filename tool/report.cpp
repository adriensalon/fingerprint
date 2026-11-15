#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <locale>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <variant>
#include <vector>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

namespace fs = std::filesystem;
namespace {
struct Number { std::string spelling; double value; };
struct Json {
    using Array = std::vector<Json>;
    using Object = std::map<std::string, Json, std::less<>>;
    std::variant<std::nullptr_t, bool, Number, std::string, Array, Object> value;
    bool is_null() const { return std::holds_alternative<std::nullptr_t>(value); }
    const Object& object() const {
        if (auto p = std::get_if<Object>(&value)) return *p;
        throw std::runtime_error("expected a JSON object");
    }
    const Array& array() const {
        if (auto p = std::get_if<Array>(&value)) return *p;
        throw std::runtime_error("expected a JSON array");
    }
    const Json& at(std::string_view key) const {
        const auto& items = object();
        auto it = items.find(key);
        if (it == items.end()) throw std::runtime_error("missing JSON field '" + std::string(key) + "'");
        return it->second;
    }
    std::string string() const {
        if (auto p = std::get_if<std::string>(&value)) return *p;
        throw std::runtime_error("expected a JSON string");
    }
    bool boolean() const {
        if (auto p = std::get_if<bool>(&value)) return *p;
        throw std::runtime_error("expected a JSON boolean");
    }
    double number() const {
        if (auto p = std::get_if<Number>(&value)) return p->value;
        throw std::runtime_error("expected a JSON number");
    }
    std::uint64_t integer() const {
        if (auto p = std::get_if<Number>(&value)) {
            std::uint64_t result{};
            const auto& text = p->spelling;
            auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), result);
            if (error == std::errc{} && end == text.data() + text.size()) return result;
        }
        throw std::runtime_error("expected a nonnegative JSON integer");
    }
};

class JsonParser {
    std::string_view text;
    std::size_t pos = 0;
    [[noreturn]] void fail(std::string_view message) const {
        std::size_t line = 1, column = 1;
        for (std::size_t i = 0; i < pos; ++i) {
            if (text[i] == '\n') { ++line; column = 1; } else ++column;
        }
        throw std::runtime_error("JSON line " + std::to_string(line) + ", column " + std::to_string(column) + ": " + std::string(message));
    }
    char peek() const { return pos < text.size() ? text[pos] : '\0'; }
    void whitespace() { while (pos < text.size() && (text[pos] == ' ' || text[pos] == '\t' || text[pos] == '\n' || text[pos] == '\r')) ++pos; }
    bool take(char c) { if (pos < text.size() && text[pos] == c) { ++pos; return true; } return false; }
    void expect(char c) { if (!take(c)) fail(std::string("expected '") + c + "'"); }
    std::uint32_t hex4() {
        std::uint32_t result = 0;
        for (int i = 0; i < 4; ++i) {
            if (pos == text.size()) fail("incomplete Unicode escape");
            unsigned char c = static_cast<unsigned char>(text[pos++]);
            int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
            if (digit < 0) fail("invalid Unicode escape");
            result = result * 16 + static_cast<unsigned>(digit);
        }
        return result;
    }
    static void utf8(std::string& result, std::uint32_t cp) {
        if (cp < 0x80) result += static_cast<char>(cp);
        else if (cp < 0x800) {
            result += static_cast<char>(0xc0 | (cp >> 6)); result += static_cast<char>(0x80 | (cp & 63));
        } else if (cp < 0x10000) {
            result += static_cast<char>(0xe0 | (cp >> 12)); result += static_cast<char>(0x80 | ((cp >> 6) & 63)); result += static_cast<char>(0x80 | (cp & 63));
        } else {
            result += static_cast<char>(0xf0 | (cp >> 18)); result += static_cast<char>(0x80 | ((cp >> 12) & 63));
            result += static_cast<char>(0x80 | ((cp >> 6) & 63)); result += static_cast<char>(0x80 | (cp & 63));
        }
    }
    std::string string() {
        expect('"');
        std::string result;
        while (pos < text.size()) {
            auto c = static_cast<unsigned char>(text[pos++]);
            if (c == '"') return result;
            if (c < 0x20) fail("unescaped control character");
            if (c == '\\') {
                if (pos == text.size()) fail("incomplete string escape");
                switch (text[pos++]) {
                case '"': result += '"'; break;
                case '\\': result += '\\'; break;
                case '/': result += '/'; break;
                case 'b': result += '\b'; break;
                case 'f': result += '\f'; break;
                case 'n': result += '\n'; break;
                case 'r': result += '\r'; break;
                case 't': result += '\t'; break;
                case 'u': {
                    auto cp = hex4();
                    if (cp >= 0xd800 && cp <= 0xdbff) {
                        if (!take('\\') || !take('u')) fail("missing low Unicode surrogate");
                        auto low = hex4();
                        if (low < 0xdc00 || low > 0xdfff) fail("invalid low Unicode surrogate");
                        cp = 0x10000 + ((cp - 0xd800) << 10) + low - 0xdc00;
                    } else if (cp >= 0xdc00 && cp <= 0xdfff) fail("unpaired low Unicode surrogate");
                    utf8(result, cp); break;
                }
                default: fail("invalid string escape");
                }
            } else if (c < 0x80) result += static_cast<char>(c);
            else {
                int count = c >= 0xc2 && c <= 0xdf ? 1 : c >= 0xe0 && c <= 0xef ? 2 : c >= 0xf0 && c <= 0xf4 ? 3 : -1;
                if (count < 0) fail("invalid UTF-8 lead byte");
                std::uint32_t cp = c & (count == 1 ? 31 : count == 2 ? 15 : 7);
                for (int i = 0; i < count; ++i) {
                    if (pos == text.size()) fail("incomplete UTF-8 sequence");
                    auto next = static_cast<unsigned char>(text[pos++]);
                    if ((next & 0xc0) != 0x80) fail("invalid UTF-8 continuation");
                    cp = (cp << 6) | (next & 63);
                }
                if (cp < (count == 1 ? 0x80u : count == 2 ? 0x800u : 0x10000u) || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) fail("invalid UTF-8 code point");
                utf8(result, cp);
            }
        }
        fail("unterminated string");
    }
    Json number() {
        auto start = pos;
        take('-');
        if (!take('0')) {
            if (peek() < '1' || peek() > '9') fail("invalid number");
            while (peek() >= '0' && peek() <= '9') ++pos;
        }
        if (take('.')) {
            if (peek() < '0' || peek() > '9') fail("missing fractional digits");
            while (peek() >= '0' && peek() <= '9') ++pos;
        }
        if (take('e') || take('E')) {
            if (!take('+')) take('-');
            if (peek() < '0' || peek() > '9') fail("missing exponent digits");
            while (peek() >= '0' && peek() <= '9') ++pos;
        }
        auto spelling = text.substr(start, pos - start);
        double result{};
        auto [end, error] = std::from_chars(spelling.data(), spelling.data() + spelling.size(), result);
        if (error != std::errc{} || end != spelling.data() + spelling.size() || !std::isfinite(result)) fail("number out of range");
        return Json{Number{std::string(spelling), result}};
    }
    Json value(unsigned depth) {
        if (depth > 64) fail("nesting exceeds 64 levels");
        whitespace();
        if (peek() == '"') return Json{string()};
        if (take('{')) {
            Json::Object result;
            whitespace();
            if (take('}')) return Json{std::move(result)};
            do {
                whitespace(); auto key = string(); whitespace(); expect(':');
                auto item = value(depth + 1);
                if (!result.emplace(std::move(key), std::move(item)).second) fail("duplicate object key");
                whitespace();
                if (take('}')) return Json{std::move(result)};
                expect(',');
            } while (true);
        }
        if (take('[')) {
            Json::Array result;
            whitespace();
            if (take(']')) return Json{std::move(result)};
            do {
                result.push_back(value(depth + 1)); whitespace();
                if (take(']')) return Json{std::move(result)};
                expect(',');
            } while (true);
        }
        for (auto literal : {std::string_view("true"), std::string_view("false"), std::string_view("null")}) {
            if (text.substr(pos, literal.size()) == literal) {
                pos += literal.size();
                if (literal == "null") return Json{nullptr};
                return Json{literal == "true"};
            }
        }
        return number();
    }
public:
    explicit JsonParser(std::string_view input) : text(input) {}
    Json parse() {
        if (text.starts_with("\xef\xbb\xbf")) pos = 3;
        auto result = value(0); whitespace();
        if (pos != text.size()) fail("trailing data");
        return result;
    }
};

std::string read_file(const fs::path& file) {
    std::ifstream stream(file, std::ios::binary);
    if (!stream) throw std::runtime_error("cannot open " + file.string());
    std::string text{std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
    if (stream.bad()) throw std::runtime_error("cannot read " + file.string());
    return text;
}
std::string display(std::string_view text) {
    std::string result;
    for (unsigned char c : text) {
        if (c == '\n') result += "\\n";
        else if (c == '\r') result += "\\r";
        else if (c == '\t') result += "\\t";
        else if (c < 32 || c == 127) result += '?';
        else result += static_cast<char>(c);
    }
    return result;
}
std::string joined(const auto& values, std::string_view separator = ", ") {
    std::string result;
    for (const auto& value : values) { if (!result.empty()) result += separator; result += display(value); }
    return result;
}
std::string text_or_null(const Json& value) { return value.is_null() ? "" : value.string(); }
double bounded(const Json& value, double max = 100) {
    double result = value.number();
    if (result < 0 || result > max) throw std::runtime_error("metric outside its allowed range");
    return result;
}
std::optional<double> optional_percent(const Json& value) { return value.is_null() ? std::nullopt : std::optional{bounded(value)}; }
std::set<std::string> string_set(const Json& value) {
    std::set<std::string> result;
    for (const auto& item : value.array()) {
        auto name = item.string();
        if (name.empty() || !result.insert(name).second) throw std::runtime_error("empty or duplicated annotation ID");
    }
    return result;
}
struct Rule {
    std::string name_space;
    std::set<std::string> attack, mbc;
    bool operator==(const Rule&) const = default;
};
struct Executable {
    std::string name, filename, sha256;
    std::uint64_t bytes{}, bindiff_functions{}, bsim_functions{};
    std::map<std::string, std::uint64_t> capabilities;
    bool operator==(const Executable&) const = default;
};
struct Settings {
    std::string ghidra, weight_template;
    double similarity{}, significance{};
    std::uint64_t cluster_limit{};
    bool operator==(const Settings&) const = default;
};
enum Metric { tlsh, ssdeep, bindiff, confidence, bsim, containment, capa, metric_count };
constexpr std::array<const char*, metric_count> metric_names{
    "TLSH distance", "ssdeep similarity %", "BinDiff similarity %", "BinDiff confidence %",
    "BSim similarity %", "BSim containment %", "capa name overlap %"};
struct Pair {
    std::string id, first, second, file;
    bool identical{};
    std::array<std::optional<double>, metric_count> metrics;
    std::uint64_t matched{}, functions1{}, functions2{}, ignored_clusters{};
    std::size_t shared{}, only1{}, only2{};
};
struct Corpus {
    std::map<std::string, Executable> executables;
    std::map<std::string, Rule> rules;
    std::map<std::pair<std::string, std::string>, Pair> pairs;
    std::optional<Settings> settings;
    std::optional<std::string> configuration, capa_version;
    bool configured = false;
    void add_executable(Executable exe) {
        auto it = executables.find(exe.name);
        if (it != executables.end() && it->second != exe)
            throw std::runtime_error("inconsistent input metadata or analysis for '" + exe.name + "' (stale or mixed reports)");
        for (const auto& [name, known] : executables)
            if (known.sha256 == exe.sha256 && known.bytes != exe.bytes) throw std::runtime_error("equal SHA-256 hashes have inconsistent sizes");
        executables.emplace(exe.name, std::move(exe));
    }
    void add(const fs::path& file) {
        try {
            auto json = JsonParser(read_file(file)).parse();
            auto config = text_or_null(json.at("configuration"));
            const auto& tools = json.at("tools");
            auto version = text_or_null(tools.at("capa").at("version"));
            if (configured && (*configuration != config || *capa_version != version)) throw std::runtime_error("mixed build configurations or capa versions");
            configuration = config; capa_version = version; configured = true;
            const auto& b = tools.at("bsim");
            const auto& s = b.at("settings");
            Settings current{b.at("ghidra_version").string(), s.at("template").string(), bounded(s.at("similarity_threshold"), 1), s.at("significance_threshold").number(), s.at("cluster_limit").integer()};
            if (current.significance < 0 || current.cluster_limit == 0) throw std::runtime_error("invalid BSim scoring settings");
            if (settings && *settings != current) throw std::runtime_error("mixed BSim scoring settings");
            settings = current;
            std::array<Executable, 2> inputs;
            std::size_t shared = 0;
            for (const auto& [name, entry] : tools.at("capa").at("capabilities").object()) {
                if (name.empty()) throw std::runtime_error("empty capability name");
                Rule rule{text_or_null(entry.at("namespace")), string_set(entry.at("attack")), string_set(entry.at("mbc"))};
                if (auto it = rules.find(name); it != rules.end() && it->second != rule) throw std::runtime_error("inconsistent capa metadata for '" + name + "'");
                rules.emplace(name, std::move(rule));
                auto a = entry.at("matches").at("input1").integer();
                auto c = entry.at("matches").at("input2").integer();
                if (a == 0 && c == 0) throw std::runtime_error("capability does not match either input");
                if (a) inputs[0].capabilities.emplace(name, a);
                if (c) inputs[1].capabilities.emplace(name, c);
                if (a && c) ++shared;
            }
            for (std::size_t i = 0; i < 2; ++i) {
                const auto key = i == 0 ? "input1" : "input2";
                const auto& meta = json.at("inputs").at(key);
                auto& exe = inputs[i];
                exe.filename = meta.at("filename").string(); exe.name = text_or_null(meta.at("target"));
                if (exe.name.empty()) exe.name = exe.filename;
                exe.sha256 = meta.at("sha256").string(); exe.bytes = meta.at("size_bytes").integer();
                if (exe.name.empty() || exe.filename.empty() || exe.sha256.size() != 64 || exe.sha256.find_first_not_of("0123456789abcdef") != std::string::npos) throw std::runtime_error("invalid executable identity");
                exe.bsim_functions = b.at("functions").at(key).integer();
                exe.bindiff_functions = tools.at("bindiff").at("functions").at(key).integer();
            }
            Pair p;
            p.first = inputs[0].name; p.second = inputs[1].name; p.file = file.filename().string();
            if (p.first == p.second) throw std::runtime_error("self-pair is not a comparison between distinct targets");
            p.identical = tools.at("sha256").at("identical").boolean();
            if (p.identical != (inputs[0].sha256 == inputs[1].sha256)) throw std::runtime_error("SHA-256 identity flag disagrees with the input hashes");
            p.metrics[tlsh] = static_cast<double>(tools.at("tlsh").at("distance").integer());
            p.metrics[ssdeep] = bounded(tools.at("ssdeep").at("similarity_percent"));
            p.metrics[bindiff] = bounded(tools.at("bindiff").at("similarity_percent"));
            p.metrics[confidence] = bounded(tools.at("bindiff").at("confidence_percent"));
            p.metrics[bsim] = optional_percent(b.at("similarity_percent")); p.metrics[containment] = optional_percent(b.at("containment_percent"));
            p.matched = tools.at("bindiff").at("functions").at("matched").integer();
            p.functions1 = inputs[0].bindiff_functions; p.functions2 = inputs[1].bindiff_functions;
            if (p.matched > std::min(p.functions1, p.functions2)) throw std::runtime_error("matched function count exceeds input function counts");
            p.ignored_clusters = b.at("ignored_clusters").integer();
            p.shared = shared; p.only1 = inputs[0].capabilities.size() - shared; p.only2 = inputs[1].capabilities.size() - shared;
            auto total = shared + p.only1 + p.only2;
            if (total) p.metrics[capa] = 100.0 * static_cast<double>(shared) / static_cast<double>(total);
            add_executable(std::move(inputs[0])); add_executable(std::move(inputs[1]));
            auto key = std::minmax(p.first, p.second);
            if (!pairs.emplace(std::make_pair(key.first, key.second), std::move(p)).second) throw std::runtime_error("duplicate unordered executable pair");
        } catch (const std::exception& error) { throw std::runtime_error(file.string() + ": " + error.what()); }
    }
    void validate(std::optional<std::size_t> expected, const std::optional<std::string>& config) {
        auto n = executables.size();
        if (n < 2 || (expected && *expected != n)) throw std::runtime_error("unexpected executable count: " + std::to_string(n));
        if (pairs.size() != n * (n - 1) / 2) {
            for (auto a = executables.begin(); a != executables.end(); ++a)
                for (auto b = std::next(a); b != executables.end(); ++b)
                    if (!pairs.contains({a->first, b->first})) throw std::runtime_error("missing comparison: " + display(a->first) + " <-> " + display(b->first));
        }
        if (config && configuration != config) throw std::runtime_error("report configuration does not match the requested build");
        std::size_t index = 1;
        for (auto& [key, pair] : pairs) { std::ostringstream id; id << 'P' << std::setfill('0') << std::setw(2) << index++; pair.id = id.str(); }
    }
};

std::string number(std::optional<double> value, int precision = 2) {
    if (!value) return "n/a";
    std::ostringstream out; out.imbue(std::locale::classic()); out << std::fixed << std::setprecision(precision) << *value; return out.str();
}
std::string pair_label(const Pair& pair) { return pair.id + " " + display(pair.first) + " <-> " + display(pair.second); }
std::vector<const Pair*> metric_pairs(const Corpus& corpus, Metric metric, bool distinct_only = false) {
    std::vector<const Pair*> result;
    for (const auto& [key, pair] : corpus.pairs) if (pair.metrics[metric] && (!distinct_only || !pair.identical)) result.push_back(&pair);
    std::ranges::sort(result, [metric](auto a, auto b) { return *a->metrics[metric] != *b->metrics[metric] ? *a->metrics[metric] < *b->metrics[metric] : a->id < b->id; });
    return result;
}
void ranges(std::ostream& out, const Corpus& corpus, bool distinct_only) {
    out << (distinct_only ? "\nScore extremes excluding byte-identical pairs\n" : "\nScore ranges across all pairs\n");
    for (int i = 0; i < metric_count; ++i) {
        auto values = metric_pairs(corpus, static_cast<Metric>(i), distinct_only);
        out << "  " << metric_names[i] << ": ";
        if (values.empty()) { out << "n/a (no comparable pairs)\n"; continue; }
        auto minimum = *values.front()->metrics[i], maximum = *values.back()->metrics[i];
        double mean = 0;
        for (auto pair : values) mean += *pair->metrics[i] / static_cast<double>(values.size());
        auto mid = values.size() / 2;
        double median = *values[mid]->metrics[i];
        if (values.size() % 2 == 0) median = (median + *values[mid - 1]->metrics[i]) / 2;
        out << "min " << number(minimum) << ", max " << number(maximum) << ", mean " << number(mean) << ", median " << number(median) << " [" << values.size() << " pairs]\n";
        for (auto [word, score] : {std::pair{"min", minimum}, std::pair{"max", maximum}}) {
            auto example = std::ranges::find_if(values, [=](auto p) { return *p->metrics[i] == score; });
            auto ties = std::ranges::count_if(values, [=](auto p) { return *p->metrics[i] == score; });
            out << "    " << word << ": " << pair_label(**example);
            if (ties > 1) out << " (" << ties << " pairs tied)";
            out << '\n';
        }
    }
}
std::string make_report(const Corpus& corpus, bool all_pairs) {
    std::ostringstream out; out.imbue(std::locale::classic());
    std::map<std::string, std::vector<std::string>> hashes;
    std::uint64_t total_bytes = 0, distinct_bytes = 0;
    std::size_t name_width = 10;
    for (const auto& [name, exe] : corpus.executables) {
        if (exe.bytes > std::numeric_limits<std::uint64_t>::max() - total_bytes) throw std::runtime_error("total byte count overflow");
        total_bytes += exe.bytes;
        auto& group = hashes[exe.sha256];
        if (group.empty()) distinct_bytes += exe.bytes;
        group.push_back(name); name_width = std::max(name_width, display(name).size());
    }
    out << "\nFINGERPRINT\n\n" << corpus.executables.size() << " executables, " << corpus.pairs.size() << " complete pair comparisons, " << hashes.size() << " distinct SHA-256 hashes\n"
        << "Configuration: " << (corpus.configuration->empty() ? "unspecified" : display(*corpus.configuration)) << '\n'
        << "Total executable bytes: " << total_bytes << "; deduplicated bytes: " << distinct_bytes << '\n';
    out << "\nExecutables\n  " << std::left << std::setw(static_cast<int>(name_width)) << "Target" << "  Bytes      SHA-256 prefix    Functions  BSim sigs  capa rules\n";
    for (const auto& [name, exe] : corpus.executables)
        out << "  " << std::left << std::setw(static_cast<int>(name_width)) << display(name) << "  " << std::right << std::setw(9) << exe.bytes << "  " << exe.sha256.substr(0, 16)
            << "  " << std::setw(9) << exe.bindiff_functions << "  " << std::setw(9) << exe.bsim_functions << "  " << std::setw(10) << exe.capabilities.size() << '\n';
    bool duplicates = false;
    out << "\nByte identity\n";
    for (const auto& [hash, names] : hashes) if (names.size() > 1) {
        duplicates = true; out << "  [IDENTICAL SHA-256] " << joined(names) << '\n' << "    " << hash << '\n';
    }
    if (!duplicates) out << "  All executable SHA-256 hashes differ.\n";
    ranges(out, corpus, false);
    if (duplicates) ranges(out, corpus, true);
    using PairRow = std::array<std::string, 13>;
    const PairRow headings{"Pair", "First", "Second", "TLSH", "ssdeep%", "BinDiff%", "conf%", "BSim%", "contain%", "capa%", "BD funcs", "capa rules", "SHA-256"};
    std::array<std::size_t, headings.size()> widths{};
    for (std::size_t i = 0; i < headings.size(); ++i) widths[i] = headings[i].size();
    std::vector<PairRow> rows;
    std::vector<const Pair*> shown;
    for (const auto& [key, pair] : corpus.pairs) {
        if (!all_pairs && rows.size() == 40) break;
        PairRow row{pair.id, display(pair.first), display(pair.second), number(pair.metrics[tlsh], 0),
            number(pair.metrics[ssdeep]), number(pair.metrics[bindiff]), number(pair.metrics[confidence]),
            number(pair.metrics[bsim]), number(pair.metrics[containment]), number(pair.metrics[capa]),
            std::to_string(pair.matched) + '/' + std::to_string(pair.functions1) + '/' + std::to_string(pair.functions2),
            std::to_string(pair.shared) + '/' + std::to_string(pair.only1) + '/' + std::to_string(pair.only2),
            pair.identical ? "IDENTICAL" : "-"};
        for (std::size_t i = 0; i < row.size(); ++i) widths[i] = std::max(widths[i], row[i].size());
        rows.push_back(std::move(row));
        shown.push_back(&pair);
    }
    auto print_pair_row = [&](const PairRow& row) {
        out << "  ";
        for (std::size_t i = 0; i < row.size(); ++i) {
            if (i) out << "  ";
            out << (i < 3 || i == row.size() - 1 ? std::left : std::right)
                << std::setw(static_cast<int>(widths[i])) << row[i];
        }
        out << '\n';
    };
    out << "\nPair details\n";
    print_pair_row(headings);
    for (const auto& row : rows) print_pair_row(row);
    out << "  BD funcs = matched/first/second; capa rules = shared/only first/only second.\n";
    out << "\n  " << std::left << std::setw(static_cast<int>(widths[0])) << "Pair" << "  Source JSON\n";
    for (auto pair : shown)
        out << "  " << std::left << std::setw(static_cast<int>(widths[0])) << pair->id << "  " << display(pair->file) << '\n';
    if (shown.size() < corpus.pairs.size()) out << "  Showing " << shown.size() << '/' << corpus.pairs.size() << " pairs; use --all-pairs to list all rows. All statistics use every pair.\n";
    out << "\nNearest neighbours among different SHA-256 hashes\n";
    for (const auto& [name, exe] : corpus.executables) {
        out << "  " << display(name) << '\n';
        for (auto metric : {tlsh, ssdeep, bindiff, bsim}) {
            const Pair* best = nullptr;
            std::size_t ties = 0;
            for (const auto& [key, pair] : corpus.pairs) {
                if (pair.identical || !pair.metrics[metric] || (pair.first != name && pair.second != name)) continue;
                if (!best || (metric == tlsh ? *pair.metrics[metric] < *best->metrics[metric] : *pair.metrics[metric] > *best->metrics[metric])) {
                    best = &pair; ties = 1;
                } else if (*pair.metrics[metric] == *best->metrics[metric]) ++ties;
            }
            out << "    " << metric_names[metric] << ": ";
            if (!best) out << "n/a\n";
            else {
                out << display(best->first == name ? best->second : best->first) << " = " << number(best->metrics[metric]) << " [" << best->id << "]";
                if (ties > 1) out << " (" << ties << " neighbours tied)";
                out << '\n';
            }
        }
    }
    out << "\nCapability evidence (capa " << (corpus.capa_version->empty() ? "unspecified" : display(*corpus.capa_version)) << ")\n";
    if (corpus.rules.empty()) out << "  No public rules matched; empty/empty overlap is n/a.\n";
    for (const auto& [name, rule] : corpus.rules) {
        std::vector<std::string> present, absent;
        for (const auto& [exe_name, exe] : corpus.executables) {
            if (auto it = exe.capabilities.find(name); it != exe.capabilities.end()) present.push_back(exe_name + " (" + std::to_string(it->second) + ")");
            else absent.push_back(exe_name);
        }
        out << "  " << (absent.empty() ? "[COMMON] " : "[VARIES] ") << display(name);
        if (!rule.name_space.empty()) out << " [" << display(rule.name_space) << ']';
        out << "\n    matches: " << joined(present) << '\n';
        if (!absent.empty()) out << "    absent: " << joined(absent) << '\n';
        if (!rule.attack.empty()) out << "    ATT&CK: " << joined(rule.attack) << '\n';
        if (!rule.mbc.empty()) out << "    MBC: " << joined(rule.mbc) << '\n';
    }
    out << "\nInterpretation notes\n"
        << "  SHA-256 determines byte identity; lower TLSH distance means closer fingerprints.\n"
        << "  Other similarity columns use percentages; tool scales are not averaged together.\n"
        << "  capa overlap is Jaccard overlap of rule names, not a native capa score.\n"
        << "  BSim signatures: " << corpus.settings->weight_template << ", similarity threshold " << number(corpus.settings->similarity * 100)
        << "%, significance " << number(corpus.settings->significance) << ", cluster limit " << corpus.settings->cluster_limit
        << ", Ghidra " << display(corpus.settings->ghidra) << ".\n";
    for (const auto& [key, pair] : corpus.pairs) {
        if (!pair.identical && ((pair.metrics[bsim] && *pair.metrics[bsim] >= 99.995) || *pair.metrics[bindiff] >= 99.995))
            out << "  [STRUCTURE != BYTES] " << pair_label(pair) << ": a structural score reaches 100% while SHA-256 differs.\n";
        if (!pair.metrics[bsim] || !pair.metrics[containment]) out << "  [INSUFFICIENT BSIM EVIDENCE] " << pair_label(pair) << ": undefined scores are excluded from statistics.\n";
        if (pair.ignored_clusters) out << "  [LIMITED BSIM] " << pair.id << ": " << pair.ignored_clusters << " clusters excluded by scorer limits.\n";
        if (*pair.metrics[confidence] < 50) out << "  [LOW BINDIFF CONFIDENCE <50%] " << pair_label(pair) << '\n';
        if (pair.metrics[bsim] && pair.metrics[containment] && *pair.metrics[containment] - *pair.metrics[bsim] >= 20)
            out << "  [CONTAINMENT GAP >=20pp] " << pair_label(pair) << ": containment " << number(pair.metrics[containment]) << "%, whole-executable similarity " << number(pair.metrics[bsim]) << "%.\n";
        std::vector<double> similarities{*pair.metrics[ssdeep], *pair.metrics[bindiff]};
        if (pair.metrics[bsim]) similarities.push_back(*pair.metrics[bsim]);
        auto [minimum, maximum] = std::minmax_element(similarities.begin(), similarities.end());
        if (*maximum - *minimum >= 40) out << "  [CROSS-TOOL SPREAD >=40pp] " << pair_label(pair) << ": inspect the independent scores above.\n";
    }
    return out.str();
}
void write_report(const fs::path& output, const std::string& text) {
    if (!output.parent_path().empty()) fs::create_directories(output.parent_path());
    auto temporary = output; temporary += ".tmp";
    {
        std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
        if (!stream || !(stream << text) || !stream.flush()) throw std::runtime_error("cannot write " + temporary.string());
    }
#ifdef _WIN32
    if (!MoveFileExW(temporary.c_str(), output.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::system_error(static_cast<int>(GetLastError()), std::system_category(), "cannot publish " + output.string());
#else
    fs::rename(temporary, output);
#endif
}
std::size_t parse_count(std::string_view value) {
    std::size_t result{};
    auto [end, error] = std::from_chars(value.data(), value.data() + value.size(), result);
    if (error != std::errc{} || end != value.data() + value.size() || result < 2) throw std::runtime_error("--expected-targets must be an integer >=2");
    return result;
}
} // namespace

int main(int argc, char** argv) {
    try {
        std::vector<fs::path> inputs;
        std::optional<fs::path> output;
        std::optional<std::size_t> expected;
        std::optional<std::string> configuration;
        bool all_pairs = false, positional = false;
        auto argument = [&](int& index) -> std::string { if (++index == argc) throw std::runtime_error("missing option argument"); return argv[index]; };
        for (int i = 1; i < argc; ++i) {
            std::string_view arg = argv[i];
            if (!positional && arg == "--") positional = true;
            else if (!positional && arg == "--help") {
                std::cout << "Usage: fingerprint_report_tool [--expected-targets N] [--configuration=NAME]\n"
                             "       [--output FILE] [--all-pairs] [--manifest FILE] [--] pair.json ...\n";
                return 0;
            } else if (!positional && arg == "--expected-targets") expected = parse_count(argument(i));
            else if (!positional && arg.starts_with("--configuration=")) configuration = std::string(arg.substr(16));
            else if (!positional && arg == "--output") output = argument(i);
            else if (!positional && arg == "--all-pairs") all_pairs = true;
            else if (!positional && arg == "--manifest") {
                fs::path manifest = argument(i);
                std::istringstream lines(read_file(manifest));
                std::string line;
                bool first = true;
                while (std::getline(lines, line)) {
                    if (first && line.starts_with("\xef\xbb\xbf")) line.erase(0, 3);
                    first = false;
                    if (!line.empty() && line.back() == '\r') line.pop_back();
                    if (line.empty()) continue;
                    fs::path file(line);
                    inputs.push_back(file.is_relative() ? manifest.parent_path() / file : file);
                }
            } else if (!positional && arg.starts_with("--")) throw std::runtime_error("unknown option: " + std::string(arg));
            else inputs.emplace_back(argv[i]);
        }
        if (inputs.empty()) throw std::runtime_error("no comparison JSON files supplied (see --help)");
        Corpus corpus;
        for (const auto& input : inputs) corpus.add(input);
        corpus.validate(expected, configuration);
        auto report = make_report(corpus, all_pairs);
        if (output) write_report(*output, report);
        std::cout << report;
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "fingerprint report: " << error.what() << '\n';
        return 1;
    }
}
