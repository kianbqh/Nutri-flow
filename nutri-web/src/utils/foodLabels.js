export const FOOD_LABEL_ZH = {
  background: '背景',
  candy: '糖果',
  'egg tart': '蛋挞',
  'french fries': '炸薯条',
  chocolate: '巧克力',
  biscuit: '饼干',
  popcorn: '爆米花',
  pudding: '布丁',
  'ice cream': '冰淇淋',
  'cheese butter': '奶酪黄油',
  cake: '蛋糕',
  wine: '葡萄酒',
  milkshake: '奶昔',
  coffee: '咖啡',
  juice: '果汁',
  milk: '牛奶',
  tea: '茶',
  almond: '杏仁',
  'red beans': '红豆',
  cashew: '腰果',
  'dried cranberries': '蔓越莓干',
  soy: '黄豆',
  walnut: '核桃',
  peanut: '花生',
  egg: '鸡蛋',
  apple: '苹果',
  date: '枣',
  apricot: '杏子',
  avocado: '牛油果',
  banana: '香蕉',
  strawberry: '草莓',
  cherry: '樱桃',
  blueberry: '蓝莓',
  raspberry: '树莓',
  mango: '芒果',
  olives: '橄榄',
  peach: '桃子',
  lemon: '柠檬',
  pear: '梨',
  fig: '无花果',
  pineapple: '菠萝',
  grape: '葡萄',
  kiwi: '猕猴桃',
  melon: '甜瓜',
  orange: '橙子',
  watermelon: '西瓜',
  steak: '牛排',
  pork: '猪肉',
  'chicken duck': '鸡鸭肉',
  sausage: '香肠',
  'fried meat': '炸肉',
  lamb: '羊肉',
  sauce: '酱料',
  crab: '螃蟹',
  fish: '鱼',
  shellfish: '贝类',
  shrimp: '虾',
  soup: '汤',
  bread: '面包',
  corn: '玉米',
  hamburg: '汉堡',
  pizza: '披萨',
  'hanamaki baozi': '花卷包子',
  'wonton dumplings': '馄饨饺子',
  pasta: '意面',
  noodles: '面条',
  rice: '米饭',
  pie: '馅饼',
  tofu: '豆腐',
  eggplant: '茄子',
  potato: '土豆',
  garlic: '大蒜',
  cauliflower: '菜花',
  tomato: '番茄',
  kelp: '海带',
  seaweed: '海苔',
  'spring onion': '葱',
  rape: '油菜',
  ginger: '姜',
  okra: '秋葵',
  lettuce: '生菜',
  pumpkin: '南瓜',
  cucumber: '黄瓜',
  'white radish': '白萝卜',
  carrot: '胡萝卜',
  asparagus: '芦笋',
  'bamboo shoots': '竹笋',
  broccoli: '西兰花',
  'celery stick': '芹菜',
  'cilantro mint': '香菜薄荷',
  'snow peas': '荷兰豆',
  cabbage: '卷心菜',
  'bean sprouts': '豆芽',
  onion: '洋葱',
  pepper: '辣椒',
  'green beans': '四季豆',
  'french beans': '菜豆',
  'king oyster mushroom': '杏鲍菇',
  shiitake: '香菇',
  'enoki mushroom': '金针菇',
  'oyster mushroom': '平菇',
  'white button mushroom': '白蘑菇',
  salad: '沙拉',
  'other ingredients': '其他配料',
}

export const FOODSEG103_CLASS_NAMES = [
  'background', 'candy', 'egg tart', 'french fries', 'chocolate', 'biscuit',
  'popcorn', 'pudding', 'ice cream', 'cheese butter', 'cake', 'wine',
  'milkshake', 'coffee', 'juice', 'milk', 'tea', 'almond', 'red beans',
  'cashew', 'dried cranberries', 'soy', 'walnut', 'peanut', 'egg', 'apple',
  'date', 'apricot', 'avocado', 'banana', 'strawberry', 'cherry', 'blueberry',
  'raspberry', 'mango', 'olives', 'peach', 'lemon', 'pear', 'fig',
  'pineapple', 'grape', 'kiwi', 'melon', 'orange', 'watermelon', 'steak',
  'pork', 'chicken duck', 'sausage', 'fried meat', 'lamb', 'sauce', 'crab',
  'fish', 'shellfish', 'shrimp', 'soup', 'bread', 'corn', 'hamburg', 'pizza',
  'hanamaki baozi', 'wonton dumplings', 'pasta', 'noodles', 'rice', 'pie',
  'tofu', 'eggplant', 'potato', 'garlic', 'cauliflower', 'tomato', 'kelp',
  'seaweed', 'spring onion', 'rape', 'ginger', 'okra', 'lettuce', 'pumpkin',
  'cucumber', 'white radish', 'carrot', 'asparagus', 'bamboo shoots',
  'broccoli', 'celery stick', 'cilantro mint', 'snow peas', 'cabbage',
  'bean sprouts', 'onion', 'pepper', 'green beans', 'french beans',
  'king oyster mushroom', 'shiitake', 'enoki mushroom', 'oyster mushroom',
  'white button mushroom', 'salad', 'other ingredients',
]

export function looksChinese(text) {
  return /[\u4e00-\u9fff]/.test((text || '').toString())
}

export function translateFoodLabel(label) {
  const normalized = (label || '').toString().trim()
  if (!normalized) {
    return ''
  }
  return FOOD_LABEL_ZH[normalized.toLowerCase()] || normalized
}

export function resolveFoodLabel(item) {
  const candidates = [
    item?.displayLabel,
    item?.display_name,
    item?.displayName,
    item?.class_name,
    item?.className,
    item?.label,
  ]

  for (const candidate of candidates) {
    const normalized = (candidate || '').toString().trim()
    if (!normalized) {
      continue
    }
    const mapped = FOOD_LABEL_ZH[normalized.toLowerCase()]
    if (mapped) {
      return mapped
    }
    if (looksChinese(normalized)) {
      return normalized
    }
  }

  const classId = Number(item?.class_id ?? item?.classId)
  const className = Number.isInteger(classId) ? FOODSEG103_CLASS_NAMES[classId] : ''
  if (className) {
    return FOOD_LABEL_ZH[className] || className
  }

  return '未知食物'
}

export function buildFoodGroupKey(item) {
  const classId = item?.class_id ?? item?.classId ?? 'unknown'
  const rawName = [
    item?.class_name,
    item?.className,
    item?.display_name,
    item?.displayName,
    item?.label,
    item?.displayLabel,
  ].find(value => value && String(value).trim())

  return `${classId}|${(rawName || 'unknown').toString().trim().toLowerCase()}`
}
