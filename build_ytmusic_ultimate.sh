#!/bin/bash

# 本地打包脚本 - 仿照GitHub workflow

# 设置默认参数
ipa_url=""
display_name="YouTube Music"
bundle_id="com.google.ios.youtubemusic"

# 参数处理
while [[ $# -gt 0 ]]; do
    case $1 in
        --ipa-url)
            ipa_url="$2"
            shift 2
            ;;
        --display-name)
            display_name="$2"
            shift 2
            ;;
        --bundle-id)
            bundle_id="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --ipa-url PATH/URL    Path to local decrypted IPA file or URL to download"
            echo "  --display-name NAME   App name (default: YouTube Music)"
            echo "  --bundle-id ID        Bundle ID (default: com.google.ios.youtubemusic)"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# 检查必要参数
if [ -z "$ipa_url" ]; then
    echo "Error: --ipa-url is required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# 设置工作目录
WORKSPACE=$(pwd)
BUILD_DIR="$WORKSPACE/build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=== YTMusicUltimate Local Build Script ==="
echo "Working directory: $BUILD_DIR"
echo "Display name: $display_name"
echo "Bundle ID: $bundle_id"
echo ""

# 下载和验证IPA
echo "Step 1: Getting and validating IPA..."

# 检查ipa_url是本地文件还是网络URL
if [[ "$ipa_url" == http://* || "$ipa_url" == https://* ]]; then
    # 网络URL，下载文件
    echo "Downloading IPA from URL..."
    wget "$ipa_url" --no-verbose -O ytm.ipa
else
    # 本地文件，复制到构建目录
    echo "Using local IPA file..."
    if [ ! -f "$ipa_url" ]; then
        echo "Error: Local IPA file not found: $ipa_url"
        exit 1
    fi
    cp "$ipa_url" "$BUILD_DIR/ytm.ipa"
fi

file_type=$(file --mime-type -b ytm.ipa)
if [[ "$file_type" != "application/x-ios-app" && "$file_type" != "application/zip" ]]; then
    echo "Error: Validation failed: The file is not a valid IPA. Detected type: $file_type."
    exit 1
fi
echo "✓ IPA obtained and validated successfully"

# 安装依赖
echo "\nStep 2: Installing dependencies..."
brew list make > /dev/null 2>&1 || brew install make
brew list ldid > /dev/null 2>&1 || brew install ldid
echo "✓ Dependencies installed"

# 设置PATH环境变量
echo "\nStep 3: Setting up PATH..."
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
echo "✓ PATH updated"

# 设置Theos
echo "\nStep 4: Setting up Theos..."
THEOS="$BUILD_DIR/theos"

if [ -d "$THEOS" ]; then
    echo "Theos already exists. Using existing installation."
else
    echo "Cloning Theos..."
    git clone --quiet --recursive https://github.com/theos/theos.git "$THEOS"
    cd "$THEOS"
    git checkout 344ee5925df036dbd1312b783ad5a00d153c2445
    git submodule update --recursive
    cd "$BUILD_DIR"
    
    # 下载iOS SDK
    echo "Downloading iOS SDK..."
    git clone --quiet -n --depth=1 --filter=tree:0 https://github.com/theos/sdks/
    cd sdks
    git sparse-checkout set --no-cone iPhoneOS16.5.sdk
    git checkout
    mv *.sdk "$THEOS/sdks"
    cd ..
    rm -rf sdks
fi
export THEOS="$THEOS"
echo "✓ Theos setup complete"

# 安装cyan工具
echo "\nStep 5: Installing cyan tool..."
which pipx > /dev/null 2>&1 || brew install pipx
pipx ensurepath > /dev/null 2>&1
export PATH="$HOME/.local/bin:$PATH"
pipx install --force https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip > /dev/null 2>&1
echo "✓ cyan tool installed"

# 构建Tweak
echo "\nStep 6: Building Tweak for Sideloading..."
cd "$WORKSPACE"
# 明确设置THEOS环境变量，确保与GitHub Workflow一致
export THEOS="$BUILD_DIR/theos"
# 使用FINALPACKAGE=1标志并添加DEBUG=0标志与GitHub Workflow保持一致
make clean package DEBUG=0 FINALPACKAGE=1 SIDELOADING=1 > build_output.log 2>&1
build_result=$?

if [ $build_result -ne 0 ]; then
    echo "✗ Build failed. Check log: build_output.log"
    echo "Last 20 lines of build log:"
    tail -n 20 build_output.log
    exit 1
fi
echo "✓ Tweak built successfully"

# 注入tweak到IPA
echo "\nStep 7: Injecting tweak into IPA..."

# 找到生成的deb文件（选择最新版本）
tweak_package=$(ls -t packages/*.deb 2>/dev/null | head -1)
if [ -z "$tweak_package" ]; then
    echo "✗ No tweak package found in packages directory"
    exit 1
fi
echo "Found tweak package: $tweak_package"

# 执行注入
cyan -i "$BUILD_DIR/ytm.ipa" -o "$BUILD_DIR/YTMusicUltimate.ipa" -uwsf "$tweak_package" -n "$display_name" -b "$bundle_id"

if [ $? -ne 0 ]; then
    echo "✗ Failed to inject tweak into IPA"
    exit 1
fi
echo "✓ Tweak injected successfully"

# 完成
echo "\n=== Build Complete! ==="
IPA_FILE="$BUILD_DIR/YTMusicUltimate.ipa"
if [ -f "$IPA_FILE" ]; then
    echo "IPA file created: $IPA_FILE"
    echo "File size: $(du -h "$IPA_FILE" | cut -f1)"
    echo ""
    echo "To install the IPA, you can use:"
    echo "- Cydia Impactor"
    echo "- AltStore"
    echo "- Sideloadly"
    echo "- Any other IPA sideloading tool"
else
    echo "Error: IPA file was not created. Check the build logs for errors."
    exit 1
fi

echo "\n=== Build Summary ==="
echo "Build successful: ✓"
echo "IPA location: $IPA_FILE"
echo "Build time: $(date)"
