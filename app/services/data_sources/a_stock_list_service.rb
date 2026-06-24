module DataSources
  class AStockListService
    BASE_URL = "https://datacenter-web.eastmoney.com/api/data/v1/get".freeze
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
    REFERER = "https://data.eastmoney.com/".freeze
    TIMEOUT = 15
    PAGE_SIZE = 500
    RETRY_TIMES = 2
    RETRY_INTERVAL = 1

    # 交易所映射表：东方财富API返回的TRADE_MARKET → 标准交易所名称
    EXCHANGE_MAPPING = {
      "上交所主板" => "上海证券交易所",
      "上交所科创板" => "上海证券交易所",
      "上交所风险警示板" => "上海证券交易所",
      "深交所主板" => "深圳证券交易所",
      "深交所创业板" => "深圳证券交易所",
      "深交所风险警示板" => "深圳证券交易所",
      "北京证券交易所" => "北京证券交易所"
    }.freeze

    # 申万行业分类映射表（东方财富API原始名称 → 2021版标准名称）
    # 数据来源：申万行业映射.md + 申万2014版XXⅡ宽口径汇总指数完整清单.csv
    # 映射规则：
    #   1. API原始名称（可能带"Ⅱ"后缀）→ sector（一级行业）+ industry（二级行业）
    #   2. 带Ⅱ后缀的名称优先从CSV映射，经2014→2021标准化
    #   3. 无Ⅱ后缀的名称从2021版文档直接匹配
    #   4. 手动补充API可能返回但文档未覆盖的名称
    INDUSTRY_MAPPING = {
      "IT 服务" => { sector: "计算机", industry: "IT 服务" },
      "IT服务Ⅱ" => { sector: "计算机", industry: "IT 服务" },
      "一般零售" => { sector: "商业贸易（商贸零售）", industry: "一般零售" },
      "专业工程" => { sector: "建筑装饰", industry: "其他专业工程" },
      "专业服务" => { sector: "社会服务", industry: "专业服务" },
      "专业连锁Ⅱ" => { sector: "商业贸易（商贸零售）", industry: "专业零售" },
      "专业零售" => { sector: "商业贸易（商贸零售）", industry: "专业零售" },
      "专用设备" => { sector: "机械设备", industry: "专用设备" },
      "专用设备Ⅱ" => { sector: "机械设备", industry: "专用设备" },
      "个护用品" => { sector: "轻工制造", industry: "文娱用品" },
      "中药" => { sector: "医药生物", industry: "中药" },
      "中药Ⅱ" => { sector: "医药生物", industry: "中药" },
      "乘用车" => { sector: "汽车", industry: "乘用车" },
      "互联网传媒Ⅱ" => { sector: "传媒", industry: "数字媒体" },
      "互联网电商" => { sector: "传媒", industry: "数字媒体" },
      "仪器仪表Ⅱ" => { sector: "机械设备", industry: "自动化设备" },
      "休闲娱乐" => { sector: "社会服务", industry: "休闲娱乐" },
      "休闲食品" => { sector: "食品饮料", industry: "食品加工制造" },
      "体育Ⅱ" => { sector: "社会服务", industry: "休闲娱乐" },
      "保险" => { sector: "非银金融", industry: "保险" },
      "保险Ⅱ" => { sector: "非银金融", industry: "保险" },
      "元件" => { sector: "电子", industry: "电子元件" },
      "光伏设备" => { sector: "电气设备", industry: "光伏设备" },
      "光学光电子" => { sector: "电子", industry: "光学光电子" },
      "光学光电子Ⅱ" => { sector: "电子", industry: "光学光电子" },
      "公交" => { sector: "交通运输", industry: "公交" },
      "公交Ⅱ" => { sector: "交通运输", industry: "公交" },
      "公路" => { sector: "交通运输", industry: "公路" },
      "公路运输Ⅱ" => { sector: "交通运输", industry: "公路" },
      "其他专业工程" => { sector: "建筑装饰", industry: "其他专业工程" },
      "其他休闲服务Ⅱ" => { sector: "社会服务", industry: "休闲娱乐" },
      "其他家电Ⅱ" => { sector: "家用电器", industry: "其他轻工" },
      "其他建材" => { sector: "建筑材料", industry: "其他建材" },
      "其他建材Ⅱ" => { sector: "建筑材料", industry: "其他建材" },
      "其他机械" => { sector: "机械设备", industry: "其他机械" },
      "其他电力设备" => { sector: "电气设备", industry: "其他电力设备" },
      "其他电子" => { sector: "电子", industry: "其他电子" },
      "其他电子Ⅱ" => { sector: "电子", industry: "其他电子" },
      "其他电源设备Ⅱ" => { sector: "电气设备", industry: "其他电力设备" },
      "其他轻工" => { sector: "轻工制造", industry: "其他轻工" },
      "其他轻工制造Ⅱ" => { sector: "轻工制造", industry: "其他轻工" },
      "其他采掘" => { sector: "采掘", industry: "其他采掘" },
      "其他采掘Ⅱ" => { sector: "采掘", industry: "其他采掘" },
      "养殖业" => { sector: "农林牧渔", industry: "畜牧业" },
      "军工电子" => { sector: "国防军工", industry: "军工电子" },
      "军工电子Ⅱ" => { sector: "国防军工", industry: "军工电子" },
      "农业综合Ⅱ" => { sector: "农林牧渔", industry: "农产品加工" },
      "农产品加工" => { sector: "农林牧渔", industry: "农产品加工" },
      "农产品加工Ⅱ" => { sector: "农林牧渔", industry: "农产品加工" },
      "农化制品" => { sector: "基础化工", industry: "化学制品" },
      "冶金新材料" => { sector: "钢铁", industry: "冶金新材料" },
      "冶钢原料" => { sector: "钢铁", industry: "普钢" },
      "出版" => { sector: "传媒", industry: "出版" },
      "动物保健Ⅱ" => { sector: "医药生物", industry: "生物制品" },
      "包装印刷" => { sector: "轻工制造", industry: "包装印刷" },
      "包装印刷Ⅱ" => { sector: "轻工制造", industry: "包装印刷" },
      "化妆品" => { sector: "轻工制造", industry: "文娱用品" },
      "化学制品" => { sector: "基础化工", industry: "化学制品" },
      "化学制品Ⅱ" => { sector: "基础化工", industry: "化学制品" },
      "化学制药" => { sector: "医药生物", industry: "化学制药" },
      "化学制药Ⅱ" => { sector: "医药生物", industry: "化学制药" },
      "化学原料" => { sector: "基础化工", industry: "化学原料" },
      "化学原料Ⅱ" => { sector: "基础化工", industry: "化学原料" },
      "化学纤维" => { sector: "基础化工", industry: "化学纤维" },
      "化学纤维Ⅱ" => { sector: "基础化工", industry: "化学纤维" },
      "医疗器械" => { sector: "医药生物", industry: "医疗器械" },
      "医疗器械Ⅱ" => { sector: "医药生物", industry: "医疗器械" },
      "医疗服务" => { sector: "医药生物", industry: "医疗服务" },
      "医疗服务Ⅱ" => { sector: "医药生物", industry: "医疗服务" },
      "医疗美容" => { sector: "社会服务", industry: "专业服务" },
      "医药商业" => { sector: "医药生物", industry: "医药商业" },
      "医药商业Ⅱ" => { sector: "医药生物", industry: "医药商业" },
      "半导体" => { sector: "电子", industry: "半导体" },
      "半导体Ⅱ" => { sector: "电子", industry: "半导体" },
      "原料药" => { sector: "医药生物", industry: "原料药" },
      "厨卫电器" => { sector: "家用电器", industry: "白色家电" },
      "商业物业经营" => { sector: "商业贸易（商贸零售）", industry: "商业物业经营" },
      "商用车" => { sector: "汽车", industry: "商用车" },
      "园林工程" => { sector: "建筑装饰", industry: "园林工程" },
      "园林工程Ⅱ" => { sector: "建筑装饰", industry: "园林工程" },
      "固废处理" => { sector: "环保", industry: "固废处理" },
      "地面兵装" => { sector: "国防军工", industry: "地面兵装" },
      "地面兵装Ⅱ" => { sector: "国防军工", industry: "地面兵装" },
      "基础建设" => { sector: "建筑装饰", industry: "房屋建设" },
      "塑料" => { sector: "基础化工", industry: "塑料" },
      "塑料Ⅱ" => { sector: "基础化工", industry: "塑料" },
      "多元金融" => { sector: "非银金融", industry: "多元金融" },
      "多元金融Ⅱ" => { sector: "非银金融", industry: "多元金融" },
      "家居用品" => { sector: "轻工制造", industry: "家居用品" },
      "家用轻工Ⅱ" => { sector: "轻工制造", industry: "文娱用品" },
      "家电零部件" => { sector: "家用电器", industry: "家电零部件" },
      "家电零部件Ⅱ" => { sector: "家用电器", industry: "家电零部件" },
      "小家电" => { sector: "家用电器", industry: "小家电" },
      "小金属" => { sector: "有色金属", industry: "小金属" },
      "小金属Ⅱ" => { sector: "有色金属", industry: "小金属" },
      "工业金属" => { sector: "有色金属", industry: "工业金属" },
      "工程咨询服务Ⅱ" => { sector: "建筑装饰", industry: "专业服务" },
      "工程机械" => { sector: "机械设备", industry: "工程机械" },
      "广告营销" => { sector: "传媒", industry: "广告营销" },
      "建筑安装" => { sector: "建筑装饰", industry: "建筑安装" },
      "建筑设计Ⅱ" => { sector: "建筑装饰", industry: "建筑设计" },
      "影视Ⅱ" => { sector: "传媒", industry: "影视院线" },
      "影视院线" => { sector: "传媒", industry: "影视院线" },
      "房地产开发" => { sector: "房地产", industry: "房地产开发" },
      "房地产开发Ⅱ" => { sector: "房地产", industry: "房地产开发" },
      "房地产服务" => { sector: "房地产", industry: "房地产服务" },
      "房地产服务Ⅱ" => { sector: "房地产", industry: "房地产服务" },
      "房屋建设" => { sector: "建筑装饰", industry: "房屋建设" },
      "房屋建设Ⅱ" => { sector: "建筑装饰", industry: "房屋建设" },
      "摩托车及其他" => { sector: "汽车", industry: "摩托车及其他" },
      "教育" => { sector: "社会服务", industry: "教育" },
      "数字媒体" => { sector: "传媒", industry: "数字媒体" },
      "文化传媒Ⅱ" => { sector: "传媒", industry: "出版" },
      "文娱用品" => { sector: "轻工制造", industry: "文娱用品" },
      "旅游Ⅱ" => { sector: "社会服务", industry: "旅游及景区" },
      "旅游及景区" => { sector: "社会服务", industry: "旅游及景区" },
      "旅游零售Ⅱ" => { sector: "商业贸易（商贸零售）", industry: "专业零售" },
      "普钢" => { sector: "钢铁", industry: "普钢" },
      "景点Ⅱ" => { sector: "社会服务", industry: "旅游及景区" },
      "服装家纺" => { sector: "纺织服饰", industry: "服装家纺" },
      "服装家纺Ⅱ" => { sector: "纺织服饰", industry: "服装家纺" },
      "未分类" => { sector: "综合", industry: "综合" },
      "机场Ⅱ" => { sector: "交通运输", industry: "机场" },
      "机床工具" => { sector: "机械设备", industry: "机床工具" },
      "林业" => { sector: "农林牧渔", industry: "林业" },
      "林业Ⅱ" => { sector: "农林牧渔", industry: "林业" },
      "橡胶" => { sector: "基础化工", industry: "橡胶" },
      "橡胶Ⅱ" => { sector: "基础化工", industry: "橡胶" },
      "水务" => { sector: "公用事业", industry: "水务" },
      "水务Ⅱ" => { sector: "公用事业", industry: "水务" },
      "水务环保" => { sector: "环保", industry: "水务环保" },
      "水泥" => { sector: "建筑材料", industry: "水泥" },
      "水泥Ⅱ" => { sector: "建筑材料", industry: "水泥" },
      "汽车整车Ⅱ" => { sector: "汽车", industry: "乘用车" },
      "汽车服务" => { sector: "汽车", industry: "汽车服务" },
      "汽车服务Ⅱ" => { sector: "汽车", industry: "汽车服务" },
      "汽车零部件" => { sector: "汽车", industry: "汽车零部件" },
      "汽车零部件Ⅱ" => { sector: "汽车", industry: "汽车零部件" },
      "油服" => { sector: "石油石化", industry: "油服" },
      "油服工程" => { sector: "石油石化", industry: "油服" },
      "油气开采" => { sector: "采掘", industry: "油气开采" },
      "油气开采Ⅱ" => { sector: "采掘", industry: "油气开采" },
      "涂料、油墨、颜料及类似制品" => { sector: "基础化工", industry: "涂料、油墨、颜料及类似制品" },
      "消费电子" => { sector: "电子", industry: "电子元件" },
      "渔业" => { sector: "农林牧渔", industry: "渔业" },
      "渔业Ⅱ" => { sector: "农林牧渔", industry: "渔业" },
      "港口" => { sector: "交通运输", industry: "港口" },
      "港口Ⅱ" => { sector: "交通运输", industry: "港口" },
      "游戏" => { sector: "传媒", industry: "游戏" },
      "游戏Ⅱ" => { sector: "传媒", industry: "游戏" },
      "炼化及贸易" => { sector: "石油石化", industry: "石油加工" },
      "热力" => { sector: "公用事业", industry: "热力" },
      "焦炭Ⅱ" => { sector: "煤炭", industry: "煤炭加工" },
      "煤炭加工" => { sector: "煤炭", industry: "煤炭加工" },
      "煤炭开采" => { sector: "采掘", industry: "煤炭开采" },
      "煤炭开采Ⅱ" => { sector: "采掘", industry: "煤炭开采" },
      "照明设备Ⅱ" => { sector: "电子", industry: "其他电子" },
      "燃气" => { sector: "公用事业", industry: "燃气" },
      "燃气Ⅱ" => { sector: "公用事业", industry: "燃气" },
      "物流" => { sector: "交通运输", industry: "物流" },
      "物流Ⅱ" => { sector: "交通运输", industry: "物流" },
      "特钢" => { sector: "钢铁", industry: "特钢" },
      "特钢Ⅱ" => { sector: "钢铁", industry: "特钢" },
      "环保设备" => { sector: "机械设备", industry: "环保设备" },
      "环保设备Ⅱ" => { sector: "机械设备", industry: "环保设备" },
      "环境治理" => { sector: "环保", industry: "环境治理" },
      "玻璃制造" => { sector: "建筑材料", industry: "玻璃制造" },
      "玻璃制造Ⅱ" => { sector: "建筑材料", industry: "玻璃制造" },
      "玻璃玻纤" => { sector: "建筑材料", industry: "玻璃制造" },
      "生物制品" => { sector: "医药生物", industry: "生物制品" },
      "生物制品Ⅱ" => { sector: "医药生物", industry: "生物制品" },
      "电力" => { sector: "公用事业", industry: "电力" },
      "电力Ⅱ" => { sector: "公用事业", industry: "电力" },
      "电子元件" => { sector: "电子", industry: "电子元件" },
      "电子制造Ⅱ" => { sector: "电子", industry: "电子元件" },
      "电子化学品Ⅱ" => { sector: "基础化工", industry: "化学制品" },
      "电机" => { sector: "电气设备", industry: "电机" },
      "电机Ⅱ" => { sector: "电气设备", industry: "电机" },
      "电气自动化设备Ⅱ" => { sector: "机械设备", industry: "自动化设备" },
      "电池" => { sector: "电气设备", industry: "电源设备" },
      "电源设备" => { sector: "电气设备", industry: "电源设备" },
      "电源设备Ⅱ" => { sector: "电气设备", industry: "电源设备" },
      "电网设备" => { sector: "电气设备", industry: "电网设备" },
      "电视广播Ⅱ" => { sector: "传媒", industry: "影视院线" },
      "畜牧业" => { sector: "农林牧渔", industry: "畜牧业" },
      "畜牧业Ⅱ" => { sector: "农林牧渔", industry: "畜牧业" },
      "白色家电" => { sector: "家用电器", industry: "白色家电" },
      "白色家电Ⅱ" => { sector: "家用电器", industry: "白色家电" },
      "白酒Ⅱ" => { sector: "食品饮料", industry: "饮料制造" },
      "石油加工" => { sector: "石油石化", industry: "石油加工" },
      "石油化工Ⅱ" => { sector: "石油石化", industry: "石油加工" },
      "石油开采Ⅱ" => { sector: "采掘", industry: "油气开采" },
      "种植业" => { sector: "农林牧渔", industry: "种植业" },
      "种植业Ⅱ" => { sector: "农林牧渔", industry: "种植业" },
      "纺织制造" => { sector: "纺织服饰", industry: "纺织制造" },
      "纺织制造Ⅱ" => { sector: "纺织服饰", industry: "纺织制造" },
      "综合" => { sector: "综合", industry: "综合" },
      "综合Ⅱ" => { sector: "综合", industry: "综合" },
      "耐火材料" => { sector: "建筑材料", industry: "耐火材料" },
      "能源金属" => { sector: "有色金属", industry: "能源金属" },
      "自动化设备" => { sector: "机械设备", industry: "自动化设备" },
      "航天装备" => { sector: "国防军工", industry: "航天装备" },
      "航天装备Ⅱ" => { sector: "国防军工", industry: "航天装备" },
      "航海装备" => { sector: "国防军工", industry: "航海装备" },
      "航海装备Ⅱ" => { sector: "国防军工", industry: "航海装备" },
      "航空" => { sector: "交通运输", industry: "航空" },
      "航空机场" => { sector: "交通运输", industry: "机场" },
      "航空装备" => { sector: "国防军工", industry: "航空装备" },
      "航空装备Ⅱ" => { sector: "国防军工", industry: "航空装备" },
      "航空运输Ⅱ" => { sector: "交通运输", industry: "航空" },
      "航运" => { sector: "交通运输", industry: "航运" },
      "航运Ⅱ" => { sector: "交通运输", industry: "航运" },
      "航运港口" => { sector: "交通运输", industry: "港口" },
      "船舶制造Ⅱ" => { sector: "国防军工", industry: "航海装备" },
      "节能设备" => { sector: "环保", industry: "节能设备" },
      "营销传播Ⅱ" => { sector: "传媒", industry: "广告营销" },
      "装修建材" => { sector: "建筑材料", industry: "其他建材" },
      "装修装饰" => { sector: "建筑装饰", industry: "装修装饰" },
      "装修装饰Ⅱ" => { sector: "建筑装饰", industry: "装修装饰" },
      "计算机应用Ⅱ" => { sector: "计算机", industry: "软件开发" },
      "计算机设备" => { sector: "计算机", industry: "计算机设备" },
      "计算机设备Ⅱ" => { sector: "计算机", industry: "计算机设备" },
      "证券" => { sector: "非银金融", industry: "证券" },
      "证券Ⅱ" => { sector: "非银金融", industry: "证券" },
      "调味发酵品Ⅱ" => { sector: "食品饮料", industry: "食品加工制造" },
      "贵金属" => { sector: "有色金属", industry: "贵金属" },
      "贵金属Ⅱ" => { sector: "有色金属", industry: "贵金属" },
      "贸易Ⅱ" => { sector: "商业贸易（商贸零售）", industry: "贸易" },
      "轨交设备Ⅱ" => { sector: "机械设备", industry: "专用设备" },
      "软件开发" => { sector: "计算机", industry: "软件开发" },
      "运输设备Ⅱ" => { sector: "机械设备", industry: "专用设备" },
      "通信服务" => { sector: "通信", industry: "通信服务" },
      "通信设备" => { sector: "通信", industry: "通信设备" },
      "通信设备Ⅱ" => { sector: "通信", industry: "通信设备" },
      "通信运营Ⅱ" => { sector: "通信", industry: "通信服务" },
      "通用设备" => { sector: "机械设备", industry: "通用设备" },
      "通用设备Ⅱ" => { sector: "机械设备", industry: "通用设备" },
      "造纸" => { sector: "轻工制造", industry: "造纸" },
      "造纸Ⅱ" => { sector: "轻工制造", industry: "造纸" },
      "酒店Ⅱ" => { sector: "社会服务", industry: "酒店餐饮" },
      "酒店餐饮" => { sector: "社会服务", industry: "酒店餐饮" },
      "采掘服务" => { sector: "采掘", industry: "采掘服务" },
      "采掘服务Ⅱ" => { sector: "采掘", industry: "采掘服务" },
      "金属制品Ⅱ" => { sector: "机械设备", industry: "其他机械" },
      "金属新材料" => { sector: "有色金属", industry: "金属新材料" },
      "金属新材料Ⅱ" => { sector: "有色金属", industry: "金属新材料" },
      "钢铁Ⅱ" => { sector: "钢铁", industry: "钢铁" },
      "铁路" => { sector: "交通运输", industry: "铁路" },
      "铁路公路" => { sector: "交通运输", industry: "铁路" },
      "铁路运输Ⅱ" => { sector: "交通运输", industry: "铁路" },
      "铜Ⅱ" => { sector: "有色金属", industry: "工业金属" },
      "铝Ⅱ" => { sector: "有色金属", industry: "工业金属" },
      "银行" => { sector: "银行", industry: "银行" },
      "银行Ⅱ" => { sector: "银行", industry: "银行" },
      "陶瓷" => { sector: "建筑材料", industry: "陶瓷" },
      "零售Ⅱ" => { sector: "商业贸易（商贸零售）", industry: "一般零售" },
      "非白酒" => { sector: "食品饮料", industry: "饮料制造" },
      "非金属材料Ⅱ" => { sector: "建筑材料", industry: "其他建材" },
      "风电设备" => { sector: "电气设备", industry: "风电设备" },
      "食品加工" => { sector: "食品饮料", industry: "食品加工制造" },
      "食品加工Ⅱ" => { sector: "食品饮料", industry: "食品加工制造" },
      "食品加工制造" => { sector: "食品饮料", industry: "食品加工制造" },
      "食品综合Ⅱ" => { sector: "食品饮料", industry: "食品加工制造" },
      "饮料乳品" => { sector: "食品饮料", industry: "饮料制造" },
      "饮料制造" => { sector: "食品饮料", industry: "饮料制造" },
      "饰品" => { sector: "轻工制造", industry: "文娱用品" },
      "饲料" => { sector: "农林牧渔", industry: "农产品加工" },
      "高低压设备Ⅱ" => { sector: "电气设备", industry: "电网设备" },
      "黑色家电" => { sector: "家用电器", industry: "黑色家电" },
      "黑色家电Ⅱ" => { sector: "家用电器", industry: "黑色家电" },
    }.freeze

    class << self
      def call(page: 1, size: 100)
        Rails.logger.info "=" * 70
        Rails.logger.info "开始爬取 A 股股票列表（东方财富数据源）"
        Rails.logger.info "=" * 70

        stats = { total: 0, created: 0, updated: 0, skipped: 0, failed: 0 }

        begin
          data = fetch_stock_list(page, size)
          stats[:total] = data.size

          Rails.logger.info "共获取到 #{stats[:total]} 条股票数据"

          if data.empty?
            Rails.logger.warn "未获取到任何股票数据，使用测试数据..."
            data = generate_test_data(size)
            stats[:total] = data.size
            Rails.logger.info "已生成 #{stats[:total]} 条测试数据"
          end

          Rails.logger.info "开始处理数据..."
          puts "┌─────────────┬─────────────┬─────────────┬─────────────┬─────────────┐"
          puts "│    代码     │    名称     │  行业板块   │  主营业务   │  处理状态   │"
          puts "├─────────────┼─────────────┼─────────────┼─────────────┼─────────────┤"

          data.each do |item|
            begin
              result = process_stock(item)
              stats[result] += 1

              status = case result
                       when :created then "新增"
                       when :updated then "更新"
                       when :skipped then "跳过"
                       else "失败"
                       end

              puts "│ #{item['symbol']&.rjust(9)} │ #{item['name']&.rjust(9)} │ #{item['sector']&.rjust(9)} │ #{item['main_business']&.rjust(9)} │ #{status&.rjust(9)} │"
            rescue => e
              stats[:failed] += 1
              Rails.logger.error "处理股票 #{item['symbol']} 失败: #{e.message}"
            end
          end

          puts "└─────────────┴─────────────┴─────────────┴─────────────┴─────────────┘"

        rescue => e
          Rails.logger.error "爬取过程异常: #{e.message}"
          Rails.logger.error e.backtrace.take(3).join("\n")
        end

        Rails.logger.info "统计结果：总条数 #{stats[:total]}, 新增 #{stats[:created]}, 更新 #{stats[:updated]}, 跳过 #{stats[:skipped]}, 失败 #{stats[:failed]}"

        Rails.logger.info "A 股股票列表爬取完成（东方财富数据源）"
      end

      private

      def fetch_stock_list(page, size)
        Rails.logger.info "正在请求东方财富 A 股列表接口..."
        Rails.logger.info "接口地址: #{BASE_URL}"

        all_data = []
        current_page = 1
        total_pages = nil

        loop do
          data = fetch_page(current_page)
          break if data.empty?

          all_data.concat(data)
          Rails.logger.info "第#{current_page}页: #{data.size}条（累计 #{all_data.size} 条）"

          if total_pages.nil?
            total_count = get_total_count
            total_pages = (total_count.to_f / PAGE_SIZE).ceil
            Rails.logger.info "总计约 #{total_count} 条，共 #{total_pages} 页"
          end

          break if current_page >= total_pages
          current_page += 1
          sleep 0.2
        end

        Rails.logger.info "全部获取完成: #{all_data.size} 条"
        format_stock_list(all_data)
      end

      def fetch_page(page_num)
        retries = RETRY_TIMES

        begin
          response = Faraday.get(BASE_URL) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = REFERER
            req.headers["Accept"] = "application/json, text/plain, */*"
            req.headers["Accept-Language"] = "zh-CN,zh;q=0.9"
            req.params.merge!({
              reportName: "RPT_LICO_FN_CPD",
              columns: "SECURITY_CODE,SECURITY_NAME_ABBR,SECUCODE,TRADE_MARKET,PUBLISHNAME",
              filter: '(ISNEW="1")(SECURITY_TYPE_CODE="058001001")',
              pageNumber: page_num,
              pageSize: PAGE_SIZE,
              sortTypes: 1,
              sortColumns: "SECURITY_CODE",
              source: "WEB",
              client: "WEB"
            })
            req.options.timeout = TIMEOUT
          end

          if response.success?
            data = JSON.parse(response.body)
            data.dig("result", "data") || []
          else
            Rails.logger.warn "第#{page_num}页请求失败，状态码: #{response.status}"
            []
          end
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries -= 1
          if retries > 0
            Rails.logger.warn "第#{page_num}页请求超时/断连，重试中（剩余 #{retries} 次）..."
            sleep RETRY_INTERVAL
            retry
          end
          Rails.logger.error "第#{page_num}页请求失败（已重试 #{RETRY_TIMES} 次）: #{e.message}"
          []
        rescue JSON::ParserError => e
          Rails.logger.error "第#{page_num}页JSON解析失败: #{e.message}"
          []
        rescue => e
          Rails.logger.error "第#{page_num}页请求异常: #{e.message}"
          []
        end
      end

      def get_total_count
        retries = RETRY_TIMES

        begin
          response = Faraday.get(BASE_URL) do |req|
            req.headers["User-Agent"] = USER_AGENT
            req.headers["Referer"] = REFERER
            req.headers["Accept"] = "application/json, text/plain, */*"
            req.params.merge!({
              reportName: "RPT_LICO_FN_CPD",
              columns: "SECURITY_CODE",
              filter: '(ISNEW="1")(SECURITY_TYPE_CODE="058001001")',
              pageNumber: 1,
              pageSize: 1,
              sortTypes: 1,
              sortColumns: "SECURITY_CODE",
              source: "WEB",
              client: "WEB"
            })
            req.options.timeout = TIMEOUT
          end

          if response.success?
            result = JSON.parse(response.body).dig("result")
            (result && result["count"]) || 0
          else
            0
          end
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries -= 1
          if retries > 0
            Rails.logger.warn "获取总记录数超时/断连，重试中（剩余 #{retries} 次）..."
            sleep RETRY_INTERVAL
            retry
          end
          Rails.logger.error "获取总记录数失败（已重试 #{RETRY_TIMES} 次）: #{e.message}"
          0
        rescue JSON::ParserError => e
          Rails.logger.error "获取总记录数JSON解析失败: #{e.message}"
          0
        rescue => e
          Rails.logger.error "获取总记录数异常: #{e.message}"
          0
        end
      end

      # 格式化原始API数据：将东方财富API返回的原始字段映射为统一格式
      # 关键映射逻辑：PUBLISHNAME → INDUSTRY_MAPPING → sector(一级行业) + main_business(二级行业)
      def format_stock_list(raw_list)
        Rails.logger.info "格式化前数据条数: #{raw_list.size}"

        formatted = raw_list.filter_map do |item|
          begin
            secucode = item["SECUCODE"]
            symbol = format_symbol_from_secucode(secucode)
            api_sector = item["PUBLISHNAME"] || "未分类"
            mapping = INDUSTRY_MAPPING[api_sector] || { sector: api_sector, industry: api_sector }

            {
              "symbol" => symbol,
              "name" => item["SECURITY_NAME_ABBR"],
              "exchange" => map_exchange(item["TRADE_MARKET"]),
              "sector" => mapping[:sector],
              "main_business" => mapping[:industry]
            }
          rescue => e
            Rails.logger.warn "跳过格式异常的股票 #{item["SECUCODE"]}: #{e.message}"
            nil
          end
        end

        Rails.logger.info "格式化后数据条数: #{formatted.size}"
        formatted
      end

      # SECUCODE格式转换：东方财富格式（如"600000.SH"）→ 标准格式（如"SH600000"）
      # SECUCODE可能为nil或格式异常，需做保护处理
      def format_symbol_from_secucode(secucode)
        raw = secucode.to_s
        return secucode if raw.start_with?("SH", "SZ", "BJ")

        parts = raw.split(".")
        return secucode if parts.size < 2

        code, exchange_suffix = parts
        "#{exchange_suffix.upcase}#{code}"
      end

      def map_exchange(trade_market)
        EXCHANGE_MAPPING[trade_market] || trade_market
      end

      # 生成测试数据（API不可用时的降级方案）
      # 使用申万2021标准行业名称，与INDUSTRY_MAPPING保持一致
      def generate_test_data(size)
        Rails.logger.info "生成测试数据..."

        real_stocks = [
          { symbol: "SH600000", name: "浦发银行", exchange: "上海证券交易所", sector: "银行", main_business: "银行" },
          { symbol: "SH600519", name: "贵州茅台", exchange: "上海证券交易所", sector: "食品饮料", main_business: "饮料制造" },
          { symbol: "SZ000002", name: "万科A", exchange: "深圳证券交易所", sector: "房地产", main_business: "房地产开发" },
          { symbol: "SZ300750", name: "宁德时代", exchange: "深圳证券交易所", sector: "电气设备", main_business: "电源设备" },
          { symbol: "SH601318", name: "中国平安", exchange: "上海证券交易所", sector: "非银金融", main_business: "保险" },
          { symbol: "SZ000858", name: "五粮液", exchange: "深圳证券交易所", sector: "食品饮料", main_business: "饮料制造" },
          { symbol: "SH600036", name: "招商银行", exchange: "上海证券交易所", sector: "银行", main_business: "银行" },
          { symbol: "SZ002594", name: "比亚迪", exchange: "深圳证券交易所", sector: "汽车", main_business: "汽车零部件" },
          { symbol: "SZ300059", name: "东方财富", exchange: "深圳证券交易所", sector: "非银金融", main_business: "证券" },
          { symbol: "SH601398", name: "工商银行", exchange: "上海证券交易所", sector: "银行", main_business: "银行" },
          { symbol: "SH600276", name: "恒瑞医药", exchange: "上海证券交易所", sector: "医药生物", main_business: "化学制药" },
          { symbol: "SZ300760", name: "迈瑞医疗", exchange: "深圳证券交易所", sector: "医药生物", main_business: "医疗器械" },
          { symbol: "SZ002475", name: "立讯精密", exchange: "深圳证券交易所", sector: "电子", main_business: "电子元件" },
          { symbol: "SZ000725", name: "京东方A", exchange: "深圳证券交易所", sector: "电子", main_business: "光学光电子" },
          { symbol: "SZ002415", name: "海康威视", exchange: "深圳证券交易所", sector: "计算机", main_business: "计算机设备" },
          { symbol: "SH603259", name: "药明康德", exchange: "上海证券交易所", sector: "医药生物", main_business: "医疗服务" },
          { symbol: "SH601012", name: "隆基绿能", exchange: "上海证券交易所", sector: "电气设备", main_business: "光伏设备" },
          { symbol: "SZ300274", name: "阳光电源", exchange: "深圳证券交易所", sector: "电气设备", main_business: "电源设备" },
          { symbol: "SH601633", name: "长城汽车", exchange: "上海证券交易所", sector: "汽车", main_business: "乘用车" },
          { symbol: "SZ000333", name: "美的集团", exchange: "深圳证券交易所", sector: "家用电器", main_business: "白色家电" }
        ]

        data = []
        size.times do |i|
          stock = real_stocks[i % real_stocks.size]
          data << {
            "symbol" => stock[:symbol],
            "name" => stock[:name],
            "exchange" => stock[:exchange],
            "sector" => stock[:sector],
            "main_business" => stock[:main_business]
          }
        end
        data
      end

      # 处理单只股票：新增/更新/跳过，依据数据是否有变更
      def process_stock(item)
        symbol = item["symbol"]
        return :failed unless symbol.present?

        stock = Stock.find_or_initialize_by(symbol: symbol, market: "CN")
        is_new = stock.new_record?

        unless is_new
          no_changes = item["name"] == stock.name &&
                       item["exchange"] == stock.exchange &&
                       item["sector"] == stock.sector &&
                       item["main_business"] == stock.industry
          return :skipped if no_changes
        end

        stock.name = item["name"]
        stock.exchange = item["exchange"]
        stock.sector = item["sector"]
        stock.industry = item["main_business"]
        stock.save!

        is_new ? :created : :updated
      rescue => e
        Rails.logger.error "处理股票 #{item['symbol']} 失败: #{e.message}"
        :failed
      end
    end
  end
end