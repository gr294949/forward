#!/bin/bash
# 集成测试脚本 - 验证整个工作流

set -e

echo "🧪 开始集成测试..."

# 测试1: 验证update.sh
./scripts/test_incremental.sh

# 测试2: 验证aggregate.sh
./scripts/aggregate.sh

# 测试3: 验证版本逻辑
./scripts/test_version_logic.sh

# 测试4: 验证最终输出
if [ -f "widgets.fwd" ]; then
    module_count=$(jq '.widgets | length' widgets.fwd)
    echo "✅ 最终文件包含 $module_count 个模块"
else
    echo "❌ 最终文件未生成"
    exit 1
fi

echo "🎉 所有测试通过！"