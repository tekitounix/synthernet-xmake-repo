// C++命名規則の実例
#include <cstddef>
#include <cstdint>
#include <memory>
#include <type_traits>
#include <utility>
#include <vector>

#define MIDI_ASSERT(x) // マクロ: UPPER_CASE

namespace midi_core { // 名前空間: snake_case

// 型: PascalCase
class MidiParser {
  public:
    // メソッド: snake_case
    void parse_message(uint8_t* buffer, size_t size);
    bool is_valid() const;

  private:
    // メンバ変数: snake_case
    int current_channel;
    bool is_running;

    // クラス定数: snake_case (constexpr)
    static constexpr int default_channel = 0;
};

// 列挙型: PascalCase, 列挙値: UPPER_CASE
enum class MessageType { NOTE_ON, NOTE_OFF, CONTROL_CHANGE };

// グローバル定数: snake_case (constexpr)
constexpr int max_channels = 16;

// 静的変数: snake_case
static int global_counter = 0;

// 使用例
void use_globals() {
    global_counter++;
    static_cast<void>(max_channels);
}

// 型エイリアス: PascalCase
using MessagePtr = std::unique_ptr<uint8_t[]>;

// 関数: snake_case, パラメータ: snake_case
void process_data(const uint8_t* data_buffer, size_t buffer_size) {
    // ローカル変数: snake_case
    int message_count = static_cast<int>(buffer_size);

    // 頭字語は単語として扱う
    class HttpClient* http_client = nullptr;
    class UsbDevice* usb_device = nullptr;
    static_cast<void>(http_client);
    static_cast<void>(usb_device);

    // ラムダ: snake_case
    auto parse_lambda = [message_count](int channel_id) -> bool {
        // ラムダ内変数: snake_case
        bool is_valid_channel = (channel_id >= 0);
        return is_valid_channel && (channel_id < message_count);
    };

    // 構造化束縛 (C++17): snake_case
    auto [first_byte, second_byte] = std::make_pair(data_buffer[0], data_buffer[1]);
    static_cast<void>(first_byte);
    static_cast<void>(second_byte);

    // range-based for: snake_case
    std::vector<int> channel_list = {0, 1, 2};
    for (const auto& current_channel : channel_list) {
        parse_lambda(current_channel);
    }

    // if constexpr (C++17): snake_case
    if constexpr (sizeof(size_t) == 8) {
        constexpr size_t max_64bit_size = 0xFFFFFFFFFFFFFFFF;
        static_cast<void>(max_64bit_size);
    }
}

// テンプレート: 型パラメータはPascalCase, 値パラメータはPascalCase
template <typename MessageType, size_t BufferSize>
class MessageQueue {
  public:
    static constexpr size_t default_size = BufferSize;
    
    size_t get_size() const { return default_size; }
};

// C++20以降の機能
namespace modern_cpp {

// コンセプト: PascalCase (C++20)
// template <typename T>
// concept MidiMessage = requires(T t) { t.get_status(); };

// モジュール (C++20): snake_case
// export module midi_parser;

// requires節: snake_case (C++20)
// template <typename T>
// auto process_message(T&& message_data) -> decltype(message_data.size())
//     requires requires { message_data.size(); }
// {
//     return message_data.size();
// }

// auto戻り値型: snake_case
auto get_channel_count() -> int {
    return 16;
}

// designated initializers (C++20): snake_case
struct MidiEvent {
    int channel_id;
    int velocity;
    bool is_note_on;
};

void create_event() {
    // C++20以前でも動作する初期化
    MidiEvent event{1, 100, true};
    static_cast<void>(event);
}

// 三方比較演算子 (C++20): snake_case
class ChannelId {
    int value;

  public:
    explicit ChannelId(int val) : value(val) {}
    // auto operator<=>(const ChannelId& other) const = default; // C++20
    bool operator<(const ChannelId& other) const { return value < other.value; }
};

// コルーチン (C++20): snake_case
// #include <coroutine>
// std::suspend_always create_midi_sequence() { co_return; }

} // namespace modern_cpp

// 変数テンプレート (C++14): snake_case (constexpr)
template <typename T>
constexpr bool is_midi_type = std::is_integral_v<T>;

// 折り畳み式 (C++17): snake_case
template <typename... Args>
auto sum_channels(Args... channel_ids) {
    return (channel_ids + ...);
}

// attribute: snake_case
[[nodiscard]] int get_important_value() {
    return 42;
}

// ベンダーコード例外
namespace vendor {
struct GPIO_TypeDef {
    volatile uint32_t MODER;
};
} // namespace vendor

} // namespace midi_core