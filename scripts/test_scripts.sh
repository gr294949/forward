#!/bin/bash

# 脚本测试文件
echo "🧪 开始测试脚本..."

# 测试环境
echo "📍 当前目录: $(pwd)"
echo "📍 Git状态: $(git --version)"
echo "📍 jq版本: $(jq --version)"
echo "📍 rsync版本: $(rsync --version | head -1)"

# 测试配置文件
echo "🔍 测试配置文件..."
if [ -f "config/repos.json" ]; then
    echo "✅ 配置文件存在"
    if jq '.' config/repos.json > /dev/null 2>&1; then
        echo "✅ JSON格式正确"
        repo_count=$(jq '.repositories | length' config/repos.json)
        echo "📊 仓库数量: $repo_count"
    else
        echo "❌ JSON格式错误"
        exit 1
    fi
else
    echo "❌ 配置文件不存在"
    exit 1
fi

# 测试脚本语法
echo "🔍 测试脚本语法..."
bash -n scripts/update.sh && echo "✅ update.sh 语法正确" || echo "❌ update.sh 语法错误"
bash -n scripts/aggregate.sh && echo "✅ aggregate.sh 语法正确" || echo "❌ aggregate.sh 语法错误"

# 测试.fwd文件
echo "🔍 测试.fwd文件..."
find widgets -name "*.fwd" | while read fwd_file; do
    echo -n "检查 $fwd_file: "
    if jq '.' "$fwd_file" > /dev/null 2>&1; then
        widget_count=$(jq '.widgets | length' "$fwd_file" 2>/dev/null || echo "0")
        echo "✅ ($widget_count 个模块)"
    else
        echo "❌ JSON格式错误"
    fi
done

echo "🎉 测试完成！"
