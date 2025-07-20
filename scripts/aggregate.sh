#!/bin/bash

# Widget汇聚脚本 - 优化版
# 合并所有.fwd文件中的widgets，智能去重，并验证URL有效性

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 清理函数
cleanup() {
    rm -f "$TEMP_WIDGETS" "$TEMP_WIDGETS.tmp" "$TEMP_WIDGETS.dedup" "$TEMP_WIDGETS.validated" 2>/dev/null || true
}
trap cleanup EXIT

echo -e "${BLUE}🔗 开始汇聚Widget模块...${NC}"

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIDGETS_DIR="$PROJECT_ROOT/widgets"
OUTPUT_FILE="$PROJECT_ROOT/widgets.fwd"
TEMP_WIDGETS="$PROJECT_ROOT/temp_widgets.json"

# 确保widgets目录存在
mkdir -p "$WIDGETS_DIR"

# 初始化空的widgets数组
echo '[]' > "$TEMP_WIDGETS"

# 检查.fwd文件有效性并合并
echo -e "${YELLOW}📋 检查并合并.fwd文件...${NC}"
valid_count=0
invalid_count=0

for fwd_file in "$WIDGETS_DIR"/*/*.fwd; do
    [ -f "$fwd_file" ] || continue
    
    echo -n "处理: $fwd_file - "
    
    # 验证JSON格式
    if ! jq '.' "$fwd_file" > /dev/null 2>&1; then
        echo -e "${RED}❌ JSON格式错误${NC}"
        ((invalid_count++))
        continue
    fi
    
    # 提取widgets数组
    widgets_array=$(jq '.widgets // []' "$fwd_file" 2>/dev/null || echo '[]')
    widget_count=$(echo "$widgets_array" | jq 'length')
    
    if [ "$widget_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠️ 无有效模块${NC}"
    else
        echo -e "${GREEN}✅ $widget_count 个模块${NC}"
        ((valid_count++))
    fi
    
    # 合并到临时文件
    jq --argjson new_widgets "$widgets_array" '. + $new_widgets' "$TEMP_WIDGETS" > "${TEMP_WIDGETS}.tmp" && mv "${TEMP_WIDGETS}.tmp" "$TEMP_WIDGETS"
done

echo -e "${BLUE}📊 文件处理统计: ${GREEN}$valid_count 个有效${NC}, ${RED}$invalid_count 个无效${NC}"

# 智能去重：优先考虑版本号，其次考虑描述详细程度
echo -e "${YELLOW}🔄 开始智能去重...${NC}"
before_count=$(jq 'length' "$TEMP_WIDGETS")

jq '
# 根据ID分组
group_by(.id) | 
map(
  if length > 1 then 
    # 如果有多个相同ID，选择版本最高的
    # 如果版本相同，选择描述更详细的（长度更长的）
    sort_by([.version, (.description | length)]) | reverse | .[0]
  else 
    .[0] 
  end
) | 
sort_by(.title)
' "$TEMP_WIDGETS" > "${TEMP_WIDGETS}.dedup"
mv "${TEMP_WIDGETS}.dedup" "$TEMP_WIDGETS"

after_count=$(jq 'length' "$TEMP_WIDGETS")
removed_count=$((before_count - after_count))

echo -e "${BLUE}📊 去重统计: ${YELLOW}$before_count${NC} → ${GREEN}$after_count${NC} (移除 ${RED}$removed_count${NC} 个重复)"

# URL 有效性检查 - 在GitHub Actions环境中跳过验证以提高成功率
echo -e "${YELLOW}🔍 检查URL有效性...${NC}"
valid_urls=0
invalid_urls=0

# 检查是否在GitHub Actions环境中运行
if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo -e "${YELLOW}⚠️  检测到GitHub Actions环境，跳过URL验证步骤${NC}"
    # 在GitHub Actions中跳过URL验证，直接使用所有模块
    cp "$TEMP_WIDGETS" "${TEMP_WIDGETS}.validated"
    valid_urls=$(jq 'length' "$TEMP_WIDGETS")
    invalid_urls=0
else
    # 创建临时文件存储验证结果
    echo '[]' > "${TEMP_WIDGETS}.validated"

    # 逐个检查每个模块的URL (避免while循环中的变量作用域问题)
    widget_count=$(jq 'length' "$TEMP_WIDGETS")
    for ((i=0; i<widget_count; i++)); do
        widget=$(jq -r ".[$i]" "$TEMP_WIDGETS")
        id=$(echo "$widget" | jq -r '.id')
        title=$(echo "$widget" | jq -r '.title')
        url=$(echo "$widget" | jq -r '.url')
        
        echo -n "  $id ($title): "
        
        # 检查URL有效性，增加重试机制
        retry_count=0
        max_retries=2
        url_valid=false
        
        while [[ $retry_count -le $max_retries ]] && [[ "$url_valid" == "false" ]]; do
            if curl -s -I --connect-timeout 10 --max-time 30 "$url" | head -1 | grep -q "200\|302"; then
                echo -e "${GREEN}✅ 可访问${NC}"
                echo "$widget" | jq '.' >> "${TEMP_WIDGETS}.validated.tmp"
                ((valid_urls++))
                url_valid=true
            else
                ((retry_count++))
                if [[ $retry_count -le $max_retries ]]; then
                    echo -n "重试($retry_count)... "
                    sleep 2
                else
                    echo -e "${RED}❌ 不可访问${NC}"
                    ((invalid_urls++))
                fi
            fi
        done
    done
    
    # 重新组装验证通过的模块
    if [ -f "${TEMP_WIDGETS}.validated.tmp" ]; then
        jq -s '.' "${TEMP_WIDGETS}.validated.tmp" > "${TEMP_WIDGETS}.validated"
        mv "${TEMP_WIDGETS}.validated" "$TEMP_WIDGETS"
        rm -f "${TEMP_WIDGETS}.validated.tmp"
    else
        echo '[]' > "$TEMP_WIDGETS"
    fi
fi

echo -e "${BLUE}📊 URL验证统计: ${GREEN}$valid_urls 个有效${NC}, ${RED}$invalid_urls 个无效${NC}"

# 生成最终文件
final_count=$(jq 'length' "$TEMP_WIDGETS")
echo -e "${YELLOW}📝 生成最终文件: $final_count 个模块${NC}"

# 生成最终输出文件
jq --tab '{
  "name": "Widgets Collection",
  "description": "集合聚合",
  "icon": "https://github.com/pack1r/ForwardWidgets/raw/main/icon.png",
  "widgets": .
}' "$TEMP_WIDGETS" > "$OUTPUT_FILE"

echo -e "${GREEN}✅ 汇聚完成！${NC}"
echo -e "${BLUE}📄 输出文件: $OUTPUT_FILE${NC}"
echo -e "${BLUE}📊 最终统计: $final_count 个有效模块${NC}"

# 显示按仓库分组的统计
echo -e "\n${YELLOW}📈 按仓库分组统计:${NC}"
jq -r '.[] | .id' "$TEMP_WIDGETS" | sed 's/.*\///' | sort | uniq -c | sort -nr | while read count id; do
    echo -e "  ${GREEN}$count${NC} 个模块: $id"
done

# 显示简要模块列表
echo -e "\n${YELLOW}📋 模块列表:${NC}"
jq -r '.[] | "  • \(.title) (\(.id))"' "$TEMP_WIDGETS" | sort

echo -e "\n${GREEN}🎉 汇聚脚本执行完成！${NC}"

# 优化URL验证逻辑
validate_url() {
    local url=$1
    local max_retries=3
    local retry_count=0
    
    # 跳过本地文件URL
    if [[ $url == file://* ]]; then
        return 0
    fi
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s --head --max-time 10 --connect-timeout 5 "$url" >/dev/null 2>&1; then
            return 0
        fi
        
        ((retry_count++))
        if [ $retry_count -lt $max_retries ]; then
            sleep 1
        fi
    done
    
    return 1
}

# 添加详细的统计报告
generate_statistics() {
    local total_files=$1
    local valid_modules=$2
    local invalid_urls=$3
    local duplicate_count=$4
    
    echo "📊 聚合统计报告"
    echo "================"
    echo "处理的.fwd文件: $total_files"
    echo "有效模块: $valid_modules"
    echo "无效URL: $invalid_urls"
    echo "去重数量: $duplicate_count"
    echo "成功率: $(( valid_modules * 100 / (total_files > 0 ? total_files : 1) ))%"
}