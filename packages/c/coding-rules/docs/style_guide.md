# C++ スタイルガイド

C++プロジェクトのコーディングスタイル規則を定義します。

## 命名規則

### 型定義
| 要素 | 規則 | 例 |
|------|------|-----|
| **クラス** | `PascalCase` | `class AudioProcessor { /* ... */ };` |
| **構造体** | `PascalCase` | `struct MessageHeader { /* ... */ };` |
| **共用体** | `PascalCase` | `union DataVariant { /* ... */ };` |
| **列挙型** | `PascalCase` | `enum class ConnectionState { /* ... */ };` |
| **型エイリアス** | `PascalCase` | `using ProcessorCallback = std::function<void()>;` |
| **typedef** | `PascalCase` | `typedef std::unique_ptr<Device> DevicePtr;` |
| **コンセプト** | `PascalCase` | `template<typename T> concept Serializable = /* ... */;` |

### 関数・メソッド
| 要素 | 規則 | 例 |
|------|------|-----|
| **関数** | `snake_case` | `void process_audio_buffer(const Buffer& buffer);` |
| **メソッド** | `snake_case` | `bool is_connection_active() const noexcept;` |
| **private メソッド** | `snake_case` | `void validate_internal_state();` |
| **protected メソッド** | `snake_case` | `virtual void on_state_changed();` |
| **public メソッド** | `snake_case` | `std::string get_device_name() const;` |
| **virtual メソッド** | `snake_case` | `virtual void handle_message() = 0;` |

### 変数
| 要素 | 規則 | 例 |
|------|------|-----|
| **ローカル変数** | `snake_case` | `int buffer_size = calculate_optimal_size();` |
| **メンバー変数** | `snake_case`（プレフィックス/サフィックスなし） | `std::string device_identifier;` |
| **private メンバー** | `snake_case`（`m_` や `_` サフィックスは禁止） | `mutable std::mutex connection_mutex;` |
| **protected メンバー** | `snake_case` | `std::vector<Handler> event_handlers;` |
| **public メンバー** | `snake_case` | `const DeviceInfo device_info;` |
| **関数パラメータ** | `snake_case` | `void send_message(const Message& midi_message);` |

> **Note:** メンバー変数にプレフィックス (`m_`) やサフィックス (`_`) を使用しない。曖昧さの解消には `this->` を使用する。
| **ポインタパラメータ** | `snake_case` | `void process_data(const uint8_t* input_buffer);` |

### 定数・静的変数
| 要素 | 規則 | 例 |
|------|------|-----|
| **グローバル定数（const）** | `UPPER_CASE` | `const size_t MAX_BUFFER_SIZE = 4096;` |
| **静的定数（const）** | `UPPER_CASE` | `static const int DEFAULT_SAMPLE_RATE = 44100;` |
| **クラス定数（const）** | `UPPER_CASE` | `static const size_t BUFFER_ALIGNMENT = 16;` |
| **ローカル定数** | `snake_case` | `const auto connection_timeout = std::chrono::seconds(5);` |
| **constパラメータ** | `snake_case` | `void configure(const int sample_rate);` |
| **静的変数** | `snake_case` | `static std::atomic<int> active_connections{0};` |
| **グローバル変数** | `snake_case` | `std::unique_ptr<Logger> global_logger;` |
| **constexpr変数** | `snake_case` | `constexpr bool is_debug_build = false;` |
| **constexprグローバル** | `snake_case` | `constexpr int max_channels = 16;` |
| **constexprメンバー** | `snake_case` | `static constexpr size_t default_size = 1024;` |

### 列挙値
| 要素 | 規則 | 例 |
|------|------|-----|
| **enum値** | `UPPER_CASE` | `enum Status { CONNECTING, CONNECTED, DISCONNECTED };` |
| **enum class値** | `UPPER_CASE` | `enum class Protocol { MIDI_1_0, MIDI_2_0, CUSTOM };` |

### テンプレート
| 要素 | 規則 | 例 |
|------|------|-----|
| **型パラメータ** | `PascalCase` | `template<typename MessageType, typename HandlerType>` |
| **値パラメータ** | `PascalCase` | `template<size_t BufferSize, int ChannelCount>` |

### その他
| 要素 | 規則 | 例 |
|------|------|-----|
| **名前空間** | `snake_case` | `namespace audio_processing { /* ... */ }` |
| **inline名前空間** | `snake_case` | `inline namespace version_2 { /* ... */ }` |
| **マクロ** | `UPPER_CASE` | `#define AUDIO_ASSERT(condition, message)` |

### 頭字語の扱い
単語として扱う:
- `HttpClient` (HTTPClientではない)
- `UsbDevice` (USBDeviceではない)
- `parse_json_data()` (parse_JSON_dataではない)

### const vs constexpr の命名規則
- **const定数**: `UPPER_CASE` - 実行時に決まる定数値
- **constexpr変数**: `snake_case` - コンパイル時に決まる値（変数扱い）。`constexpr` のみ使用し、冗長な `inline constexpr` は書かない（C++17 以降は暗黙的に inline）
- **#define定数**: `UPPER_CASE` - プリプロセッサマクロ

## コードフォーマット

clang-formatにより自動的に以下のスタイルが適用されます：

- **基本スタイル**: LLVM（モダンな修正を加えて）
- **インデント**: 4スペース
- **行の長さ**: 120文字
- **ポインタ位置**: 左寄せ（`int* ptr`）
- **パラメータパッキング**: 無効（読みやすさのため）

## 例外

- システムヘッダーの警告は自動的に抑制されます
- 演算子オーバーロードとデストラクタは命名規則チェックから除外されます
- vendor/, third_party/, external/, libs/フォルダ内のコードは除外されます

## 設定ファイル

プロジェクトルートには以下の設定ファイルがシンボリックリンクとして配置されています：

- `.clang-format`: コードフォーマットのルール
- `.clang-tidy`: 命名規則と静的解析のルール
- `.clangd`: LSPサーバー（clangd）の設定

これらは `coding-rules` パッケージの `rules/coding/configs/` ディレクトリ内のテンプレートから生成される。

## IDE統合

### VS Code

`.vscode/settings.json`に追加：

```json
{
    "clang-format.executable": "clang-format",
    "clang-format.style": "file",
    "[cpp]": {
        "editor.formatOnSave": true
    }
}
```

### clangd（LSP）

プロジェクトルートの`.clangd`ファイルにより、以下のIDEで自動的にスタイルチェックが有効になります：

- VS Code（clangd拡張機能）
- Neovim（LSP設定）
- その他のLSP対応エディタ

clangdは入力中にリアルタイムで命名規則違反を表示します。