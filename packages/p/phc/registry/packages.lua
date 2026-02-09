{
    _meta = {
        schema_version = 2,
        description = "synthernet package registry — single source of truth"
    },
    ["clang-arm"] = {
        type = "github-release",
        repo = "ARM-software/LLVM-embedded-toolchain-for-Arm",
        tag_pattern = "release-%(version)",
        fallback_tag_pattern = "preview-%(version)",
        source_overrides = {
            {
                version_ge = "20.0.0",
                repo = "arm/arm-toolchain",
                tag_pattern = "release-%(version)-ATfE",
                fallback_tag_pattern = false,
                discover_from = true,
                assets = {
                    ["linux-aarch64"]   = "ATfE-%(version)-Linux-AArch64.tar.xz",
                    ["linux-x86_64"]    = "ATfE-%(version)-Linux-x86_64.tar.xz",
                    ["windows-x86_64"]  = "ATfE-%(version)-Windows-x86_64.zip",
                    ["macos-universal"] = "ATfE-%(version)-Darwin-universal.dmg",
                },
            },
        },
        versions = {"21.1.1", "21.1.0", "20.1.0", "19.1.5", "19.1.1", "18.1.3"},
        assets = {
            ["linux-aarch64"]   = "LLVM-ET-Arm-%(version)-Linux-AArch64.tar.xz",
            ["linux-x86_64"]    = "LLVM-ET-Arm-%(version)-Linux-x86_64.tar.xz",
            ["windows-x86_64"]  = "LLVM-ET-Arm-%(version)-Windows-x86_64.zip",
            ["macos-universal"] = "LLVM-ET-Arm-%(version)-Darwin-universal.dmg",
        },
        metadata = {
            kind = "toolchain",
            homepage = "https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm",
            description = "A project dedicated to building LLVM toolchain for 32-bit Arm embedded targets.",
        },
        install = "toolchain-archive",
        install_config = {
            bin_verify = {"clang --version", "clang --target=arm-none-eabi --version"},
            toolchain_def = "toolchains/xmake.lua",
            bin_check = "clang",
            dmg_search_pattern = {"ATfE", "LLVM%-ET%-Arm"},
            download_size = "~200MB",
            install_size = "~800MB",
        },
        hashes = {
            ["21.1.1"] = {
                ["linux-aarch64"]  = "dfd93d7c79f26667f4baf7f388966aa4cbfd938bc5cbcf0ae064553faf3e9604",
                ["linux-x86_64"]   = "fd7fcc2eb4c88c53b71c45f9c6aa83317d45da5c1b51b0720c66f1ac70151e6e",
                ["windows-x86_64"] = "12e21352acd6ce514df77b6c9ff77e20978cbb44d4c7f922bd44c60594869460",
                ["macos-universal"] = "2173cdb297ead08965ae1a34e4e92389b9024849b4ff4eb875652ff9667b7b2a",
            },
            ["21.1.0"] = {
                ["linux-aarch64"]  = "04969ac437ff659f2b35e73bf4be857b2ec5bb22a2025cfba28c51aab6d51d69",
                ["linux-x86_64"]   = "40b59c426e4057fbfde3260939fa67f240312661bd96c96be752033a69d41c6e",
                ["windows-x86_64"] = "dc9aa044e68614fbf3251cddd42447819480d9a2f3de50cd9be7d76ad8f3523e",
                ["macos-universal"] = "a310b4e8603bc25d71444d8a70e8ee9c2362cb4c8f4dcdb91a35fa371b45f425",
            },
            ["20.1.0"] = {
                ["linux-aarch64"]  = "2fa9220f64097b71c07e6de2917f33fda1bb736964730786e90a430fdc0fa6be",
                ["linux-x86_64"]   = "c1179396608c07bf68f3014923cfdfcd11c8402a3732f310c23d07c9a726b275",
                ["windows-x86_64"] = "0214ad4283c3b487bc96705121d06c74d6643ce3c2b3a1bad5e7c42789fe3c8f",
                ["macos-universal"] = "11505eed22ceafcb52ef3d678a0640c67af92f511a9dd14309a44a766fafd703",
            },
            ["19.1.5"] = {
                ["linux-aarch64"]  = "5e2f6b8c77464371ae2d7445114b4bdc19f56138e8aa864495181b52f57d0b85",
                ["linux-x86_64"]   = "34ee877aadc78c5e9f067e603a1bc9745ed93ca7ae5dbfc9b4406508dc153920",
                ["windows-x86_64"] = "f4b26357071a5bae0c1dfe5e0d5061595a8cc1f5d921b6595cc3b269021384eb",
                ["macos-universal"] = "0451e67dc9a9066c17f746c26654962fa3889d4df468db1245d1bae69438eaf5",
            },
            ["19.1.1"] = {
                ["linux-aarch64"]  = "0172cf1768072a398572cb1fc0bb42551d60181b3280f12c19401d94ca5162e6",
                ["linux-x86_64"]   = "f659c625302f6d3fb50f040f748206f6fd6bb1fc7e398057dd2deaf1c1f5e8d1",
                ["windows-x86_64"] = "3bf972ecff428cf9398753f7f2bef11220a0bfa4119aabdb1b6c8c9608105ee4",
                ["macos-universal"] = "32c9253ab05e111cffc1746864a3e1debffb7fbb48631da88579e4f830fca163",
            },
            ["18.1.3"] = {
                ["linux-aarch64"]  = "47cd08804e22cdd260be43a00b632f075c3e1ad5a2636537c5589713ab038505",
                ["linux-x86_64"]   = "7afae248ac33f7daee95005d1b0320774d8a5495e7acfb9bdc9475d3ad400ac9",
                ["windows-x86_64"] = "3013dcf1dba425b644e64cb4311b9b7f6ff26df01ba1fcd943105d6bb2a6e68b",
                ["macos-universal"] = "2864324ddff4d328e4818cfcd7e8c3d3970e987edf24071489f4182b80187a48",
            },
        },
    },
    ["gcc-arm"] = {
        type = "http-direct",
        base_url = "https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/%(mapped_version)/binrel",
        update_check = {
            type = "github-release",
            repo = "ARM-software/arm-gnu-toolchain-releases"
        },
        versions = {"14.3.1", "14.2.1"},
        version_map = {
            ["14.2.1"] = "14.2.rel1",
            ["14.3.1"] = "14.3.rel1"
        },
        assets = {
            ["linux-aarch64"]  = "arm-gnu-toolchain-%(mapped_version)-aarch64-arm-none-eabi.tar.xz",
            ["linux-x86_64"]   = "arm-gnu-toolchain-%(mapped_version)-x86_64-arm-none-eabi.tar.xz",
            ["windows-x86"]    = "arm-gnu-toolchain-%(mapped_version)-mingw-w64-i686-arm-none-eabi.zip",
            ["windows-x86_64"] = "arm-gnu-toolchain-%(mapped_version)-mingw-w64-x86_64-arm-none-eabi.zip",
            ["macos-x86_64"]   = "arm-gnu-toolchain-%(mapped_version)-darwin-x86_64-arm-none-eabi.tar.xz",
            ["macos-arm64"]    = "arm-gnu-toolchain-%(mapped_version)-darwin-arm64-arm-none-eabi.tar.xz"
        },
        exclusions = {
            ["14.3.1"] = {"macos-x86_64"}
        },
        metadata = {
            kind = "toolchain",
            homepage = "https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gcc-arm",
            description = "GNU Arm Embedded Toolchain"
        },
        install = "toolchain-archive",
        install_config = {
            bin_verify = {"arm-none-eabi-gcc --version", "arm-none-eabi-gcc --target-help"},
            toolchain_def = "toolchains/xmake.lua",
            bin_check = "arm-none-eabi-gcc",
            custom_download = true,
            download_size = "~130MB",
            install_size = "~1GB"
        },
        hashes = {
            ["14.3.1"] = {
                ["linux-aarch64"]  = "2d465847eb1d05f876270494f51034de9ace9abe87a4222d079f3360240184d3",
                ["linux-x86_64"]   = "8f6903f8ceb084d9227b9ef991490413014d991874a1e34074443c2a72b14dbd",
                ["windows-x86"]    = "836ebe51fd71b6542dd7884c8fb2011192464b16c28e4b38fddc9350daba5ee8",
                ["windows-x86_64"] = "864c0c8815857d68a1bbba2e5e2782255bb922845c71c97636004a3d74f60986",
                ["macos-arm64"]    = "30f4d08b219190a37cded6aa796f4549504902c53cfc3c7e044a8490b6eba1f7"
            },
            ["14.2.1"] = {
                ["linux-aarch64"]  = "87330bab085dd8749d4ed0ad633674b9dc48b237b61069e3b481abd364d0a684",
                ["linux-x86_64"]   = "62a63b981fe391a9cbad7ef51b17e49aeaa3e7b0d029b36ca1e9c3b2a9b78823",
                ["windows-x86"]    = "6facb152ce431ba9a4517e939ea46f057380f8f1e56b62e8712b3f3b87d994e1",
                ["windows-x86_64"] = "f074615953f76036e9a51b87f6577fdb4ed8e77d3322a6f68214e92e7859888f",
                ["macos-x86_64"]   = "2d9e717dd4f7751d18936ae1365d25916534105ebcb7583039eff1092b824505",
                ["macos-arm64"]    = "c7c78ffab9bebfce91d99d3c24da6bf4b81c01e16cf551eb2ff9f25b9e0a3818"
            }
        }
    },
    ["renode"] = {
        type = "github-release",
        repo = "renode/renode",
        tag_pattern = "v%(version)",
        versions = {"1.16.0"},
        assets = {
            ["linux-x86_64"]      = "renode-%(version).linux-portable-dotnet.tar.gz",
            ["linux-aarch64"]     = "renode-%(version).linux-arm64-portable-dotnet.tar.gz",
            ["macos-arm64"]       = "renode-%(version)-dotnet.osx-arm64-portable.dmg",
            ["windows-portable"]  = "renode-%(version).windows-portable-dotnet.zip"
        },
        metadata = {
            kind = "binary",
            homepage = "https://renode.io/",
            description = "Open source simulation framework for embedded systems"
        },
        install = "binary-app",
        install_config = {
            bin_verify = {"renode --version"},
            wrapper = {name = "renode", windows_name = "Renode.exe"},
            macos_app = "Renode.app/Contents/MacOS"
        },
        hashes = {
            ["1.16.0"] = {
                ["linux-x86_64"]     = "e676e4bfbafc4be6a2ee074a52d2e72ca0dc47433447839e47a160c42a3943cc",
                ["linux-aarch64"]    = "449e4add705c6c8282facbe36cdb61755c86db6d3c7dd056fcd82f5ec4e4999e",
                ["macos-arm64"]      = "93e1037c16cabf67fbd345ca8d7a30182418aa006e0b993e258bcd09df81ba21",
                ["windows-portable"] = "3aff885fbc6cae0f91a2bca5bca7be4f3107682b6d52f0e776fdd013044e58d6",
            },
        }
    }
}
