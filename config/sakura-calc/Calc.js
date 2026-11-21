.pragma library
// sakura-calc engine: a small, safe expression parser (no eval) + unit tables.
//   evaluate(text, opts) -> { ok, v, s }     opts: { deg: bool, ans: number, fx: {USD:1, EUR:..} }
//   convert(v, cat, from, to, fx) -> number
//   fmt(v) -> pretty string (thin-space groups), raw(v) -> string that parses back

// ── units ────────────────────────────────────────────────────────────
// factor = value of 1 unit in the category's base unit; temperature is special-cased
var CATS = [
    { id: "length", ru: "Длина", en: "Length", units: [
        ["mm", 0.001, "миллиметр", "millimetre"], ["cm", 0.01, "сантиметр", "centimetre"], ["m", 1, "метр", "metre"],
        ["km", 1000, "километр", "kilometre"], ["in", 0.0254, "дюйм", "inch"], ["ft", 0.3048, "фут", "foot"],
        ["yd", 0.9144, "ярд", "yard"], ["mi", 1609.344, "миля", "mile"], ["nmi", 1852, "морская миля", "nautical mile"] ] },
    { id: "mass", ru: "Масса", en: "Mass", units: [
        ["mg", 1e-6, "миллиграмм", "milligram"], ["g", 0.001, "грамм", "gram"], ["kg", 1, "килограмм", "kilogram"],
        ["t", 1000, "тонна", "tonne"], ["oz", 0.028349523125, "унция", "ounce"], ["lb", 0.45359237, "фунт", "pound"],
        ["st", 6.35029318, "стоун", "stone"] ] },
    { id: "temp", ru: "Температура", en: "Temperature", units: [
        ["°C", 1, "Цельсий", "Celsius"], ["°F", 1, "Фаренгейт", "Fahrenheit"], ["K", 1, "Кельвин", "Kelvin"] ] },
    { id: "volume", ru: "Объём", en: "Volume", units: [
        ["ml", 0.001, "миллилитр", "millilitre"], ["l", 1, "литр", "litre"], ["m³", 1000, "куб. метр", "cubic metre"],
        ["tsp", 0.00492892159375, "чайная ложка", "teaspoon"], ["tbsp", 0.01478676478125, "столовая ложка", "tablespoon"],
        ["cup", 0.2365882365, "чашка", "cup"], ["fl oz", 0.0295735295625, "жидк. унция", "fluid ounce"],
        ["pt", 0.473176473, "пинта", "pint"], ["gal", 3.785411784, "галлон", "gallon"] ] },
    { id: "area", ru: "Площадь", en: "Area", units: [
        ["cm²", 1e-4, "кв. сантиметр", "sq centimetre"], ["m²", 1, "кв. метр", "sq metre"], ["a", 100, "сотка", "are"],
        ["ha", 1e4, "гектар", "hectare"], ["km²", 1e6, "кв. километр", "sq kilometre"], ["ft²", 0.09290304, "кв. фут", "sq foot"],
        ["ac", 4046.8564224, "акр", "acre"], ["mi²", 2589988.110336, "кв. миля", "sq mile"] ] },
    { id: "speed", ru: "Скорость", en: "Speed", units: [
        ["m/s", 1, "метр/сек", "metre/second"], ["km/h", 1 / 3.6, "км/час", "km/hour"], ["mph", 0.44704, "миль/час", "miles/hour"],
        ["kn", 1852 / 3600, "узел", "knot"], ["ft/s", 0.3048, "фут/сек", "foot/second"] ] },
    { id: "data", ru: "Данные", en: "Data", units: [
        ["bit", 0.125, "бит", "bit"], ["B", 1, "байт", "byte"], ["KB", 1e3, "килобайт", "kilobyte"], ["MB", 1e6, "мегабайт", "megabyte"],
        ["GB", 1e9, "гигабайт", "gigabyte"], ["TB", 1e12, "терабайт", "terabyte"], ["KiB", 1024, "кибибайт", "kibibyte"],
        ["MiB", 1048576, "мебибайт", "mebibyte"], ["GiB", 1073741824, "гибибайт", "gibibyte"], ["TiB", 1099511627776, "тебибайт", "tebibyte"] ] },
    { id: "time", ru: "Время", en: "Time", units: [
        ["ms", 0.001, "миллисекунда", "millisecond"], ["s", 1, "секунда", "second"], ["min", 60, "минута", "minute"],
        ["h", 3600, "час", "hour"], ["d", 86400, "день", "day"], ["wk", 604800, "неделя", "week"],
        ["mo", 2629746, "месяц", "month"], ["yr", 31556952, "год", "year"] ] },
    { id: "currency", ru: "Валюта", en: "Currency", units: [] }
];

var CURRENCY_TOP = ["USD", "EUR", "RUB", "GBP", "CNY", "JPY", "KZT", "UAH", "BYN", "TRY", "CHF", "PLN", "GEL", "AMD",
                    "UZS", "KRW", "INR", "AED", "CAD", "AUD", "SEK", "NOK", "CZK", "THB", "ILS", "BRL", "MXN", "SGD", "HKD"];
var CURRENCY_NAMES = {
    USD: ["доллар США", "US dollar"], EUR: ["евро", "euro"], RUB: ["рубль", "Russian ruble"], GBP: ["фунт стерлингов", "pound sterling"],
    CNY: ["юань", "yuan"], JPY: ["иена", "yen"], KZT: ["тенге", "tenge"], UAH: ["гривна", "hryvnia"], BYN: ["белорусский рубль", "Belarusian ruble"],
    TRY: ["турецкая лира", "Turkish lira"], CHF: ["швейцарский франк", "Swiss franc"], PLN: ["злотый", "zloty"], GEL: ["лари", "lari"],
    AMD: ["драм", "dram"], UZS: ["сум", "som"], KRW: ["вона", "won"], INR: ["рупия", "rupee"], AED: ["дирхам", "dirham"],
    CAD: ["канадский доллар", "Canadian dollar"], AUD: ["австралийский доллар", "Australian dollar"], SEK: ["шведская крона", "Swedish krona"],
    NOK: ["норвежская крона", "Norwegian krone"], CZK: ["чешская крона", "Czech koruna"], THB: ["бат", "baht"], ILS: ["шекель", "shekel"],
    BRL: ["реал", "real"], MXN: ["мексиканское песо", "Mexican peso"], SGD: ["сингапурский доллар", "Singapore dollar"], HKD: ["гонконгский доллар", "HK dollar"]
};

// aliases typed inline ("5 km to mi", "100$ в руб")
var ALIAS = {
    "millimeter": "mm", "мм": "mm", "см": "cm", "м": "m", "meter": "m", "metre": "m", "км": "km", "inch": "in", "дюйм": "in", "\"": "in",
    "feet": "ft", "foot": "ft", "фут": "ft", "yard": "yd", "mile": "mi", "miles": "mi", "миль": "mi", "миля": "mi", "мили": "mi",
    "мг": "mg", "г": "g", "гр": "g", "кг": "kg", "kgs": "kg", "т": "t", "ton": "t", "tonne": "t", "lbs": "lb", "pound": "lb", "pounds": "lb", "фунт": "lb", "унц": "oz",
    "c": "°C", "°c": "°C", "℃": "°C", "celsius": "°C", "f": "°F", "°f": "°F", "℉": "°F", "fahrenheit": "°F", "k": "K", "kelvin": "K",
    "мл": "ml", "л": "l", "liter": "l", "litre": "l", "m3": "m³", "gallon": "gal", "gallons": "gal", "floz": "fl oz",
    "cm2": "cm²", "m2": "m²", "km2": "km²", "ft2": "ft²", "mi2": "mi²", "га": "ha", "acre": "ac", "acres": "ac", "сотка": "a", "соток": "a",
    "kmh": "km/h", "kph": "km/h", "км/ч": "km/h", "мс": "ms", "м/с": "m/s", "knot": "kn", "knots": "kn", "узлов": "kn",
    "b": "B", "byte": "B", "bytes": "B", "kb": "KB", "mb": "MB", "gb": "GB", "tb": "TB", "kib": "KiB", "mib": "MiB", "gib": "GiB", "tib": "TiB",
    "кб": "KB", "мб": "MB", "гб": "GB", "тб": "TB", "bits": "bit", "бит": "bit",
    "sec": "s", "сек": "s", "с": "s", "мин": "min", "minute": "min", "minutes": "min", "hour": "h", "hours": "h", "ч": "h", "час": "h", "часов": "h",
    "day": "d", "days": "d", "дн": "d", "дней": "d", "week": "wk", "weeks": "wk", "нед": "wk", "month": "mo", "months": "mo", "мес": "mo",
    "year": "yr", "years": "yr", "лет": "yr", "год": "yr",
    "$": "USD", "€": "EUR", "₽": "RUB", "руб": "RUB", "р": "RUB", "£": "GBP", "¥": "JPY", "₸": "KZT", "₴": "UAH", "₺": "TRY", "₹": "INR", "₩": "KRW",
    "доллар": "USD", "долларов": "USD", "евро": "EUR", "рублей": "RUB", "тенге": "KZT", "гривен": "UAH", "юаней": "CNY"
};

function catById(id) { for (var i = 0; i < CATS.length; i++) if (CATS[i].id === id) return CATS[i]; return null; }

function findUnit(u, fx) {
    if (!u) return null;
    var k = u.trim();
    var lc = k.toLowerCase();
    var id = ALIAS[k] || ALIAS[lc] || k;
    for (var i = 0; i < CATS.length - 1; i++) {
        var us = CATS[i].units;
        for (var j = 0; j < us.length; j++) if (us[j][0] === id) return { cat: CATS[i].id, id: id, f: us[j][1] };
    }
    for (i = 0; i < CATS.length - 1; i++) {   // case-insensitive second pass ("KM", "Mi")
        us = CATS[i].units;
        for (j = 0; j < us.length; j++) if (us[j][0].toLowerCase() === id.toLowerCase()) return { cat: CATS[i].id, id: us[j][0], f: us[j][1] };
    }
    var up = id.toUpperCase();
    if (/^[A-Z]{3}$/.test(up) && fx && fx[up]) return { cat: "currency", id: up, f: 1 / fx[up] };
    return null;
}

function toBaseTemp(v, u) { return u === "°F" ? (v - 32) * 5 / 9 : u === "K" ? v - 273.15 : v; }
function fromBaseTemp(v, u) { return u === "°F" ? v * 9 / 5 + 32 : u === "K" ? v + 273.15 : v; }

function unitFactor(cat, id, fx) {
    if (cat === "currency") return fx && fx[id] ? 1 / fx[id] : NaN;
    var c = catById(cat);
    if (!c) return NaN;
    for (var i = 0; i < c.units.length; i++) if (c.units[i][0] === id) return c.units[i][1];
    return NaN;
}

function convert(v, cat, from, to, fx) {
    if (cat === "temp") return fromBaseTemp(toBaseTemp(v, from), to);
    var a = unitFactor(cat, from, fx), b = unitFactor(cat, to, fx);
    return v * a / b;
}

// ── tokenizer ────────────────────────────────────────────────────────
var FUNCS = {
    sin: 1, cos: 1, tan: 1, asin: 1, acos: 1, atan: 1, sinh: 1, cosh: 1, tanh: 1, asinh: 1, acosh: 1, atanh: 1,
    ln: 1, log: 1, lg: 1, log2: 1, sqrt: 1, cbrt: 1, abs: 1, exp: 1, floor: 1, ceil: 1, round: 1, trunc: 1, sign: 1,
    min: 1, max: 1, pow: 1, root: 1, fact: 1, ncr: 1, npr: 1, gcd: 1, lcm: 1
};
var CONSTS = { pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI, "τ": 2 * Math.PI, phi: (1 + Math.sqrt(5)) / 2, "φ": (1 + Math.sqrt(5)) / 2 };
var ALIASF = { arcsin: "asin", arccos: "acos", arctan: "atan", tg: "tan", "√": "sqrt", "∛": "cbrt", lb: "log2" };

function normalize(s) {
    return String(s)
        .replace(/(\d) (?=\d{3}(?!\d))/g, "$1")     // "1 000 000"
        .replace(/[   _']/g, "")    // group separators
        .replace(/[×·∙⋅]/g, "*").replace(/[÷∕]/g, "/").replace(/[−--]/g, "-")
        .replace(/\*\*/g, "^")
        .replace(/²/g, "^2").replace(/³/g, "^3");
}

function tokenize(src) {
    var s = normalize(src), t = [], i = 0, depth = [];
    while (i < s.length) {
        var c = s[i];
        if (/\s/.test(c)) { i++; continue; }
        if (/[0-9.]/.test(c)) {
            var m = /^(?:\d+(?:[.,]\d+)*\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/.exec(s.slice(i));
            var txt = m[0];
            // ',' is a decimal mark unless we are inside a function call's argument list
            var inCall = depth.length && depth[depth.length - 1] === "f";
            if (txt.indexOf(",") >= 0) {
                if (inCall) txt = /^[^,]*/.exec(txt)[0];
                else if ((txt.match(/,/g) || []).length > 1 || txt.indexOf(".") >= 0) return null;
                else txt = txt.replace(",", ".");
            }
            var n = parseFloat(txt);
            if (isNaN(n)) return null;
            t.push({ t: "n", v: n });
            i += inCall ? (/^[^,]*/.exec(m[0])[0]).length : m[0].length;
            continue;
        }
        if (/[a-zA-Zπτφ√∛]/.test(c)) {
            var w = /^[√∛πτφ]|^[a-zA-Z][a-zA-Z0-9]*/.exec(s.slice(i))[0];
            i += w.length;
            var lw = w.toLowerCase();
            lw = ALIASF[lw] || ALIASF[w] || lw;
            if (lw === "mod") { t.push({ t: "o", v: "mod" }); continue; }
            t.push({ t: "id", v: lw });
            continue;
        }
        if ("+-*/^%!(),;".indexOf(c) >= 0) {
            if (c === "(") depth.push(t.length && t[t.length - 1].t === "id" && FUNCS[t[t.length - 1].v] ? "f" : "p");
            if (c === ")") depth.pop();
            t.push({ t: "o", v: c === ";" ? "," : c });
            i++;
            continue;
        }
        return null;
    }
    return t;
}

// ── parser / evaluator (recursive descent, evaluates as it goes) ─────
function Parser(toks, opts) { this.t = toks; this.i = 0; this.o = opts || {}; }
Parser.prototype.peek = function () { return this.t[this.i]; };
Parser.prototype.isOp = function (v) { var p = this.t[this.i]; return p && p.t === "o" && p.v === v; };
Parser.prototype.fail = function () { throw new Error("syntax"); };
Parser.prototype.startsOperand = function () {
    var p = this.peek();
    return p && (p.t === "n" || p.t === "id" || (p.t === "o" && p.v === "("));
};

Parser.prototype.add = function () {
    var l = this.mul();
    for (;;) {
        if (this.isOp("+") || this.isOp("-")) {
            var op = this.t[this.i++].v;
            var r = this.mul();
            var rv = r.pct ? l.v * r.v : r.v;      // 200 + 10% = 220
            l = { v: op === "+" ? l.v + rv : l.v - rv };
        } else return l;
    }
};
Parser.prototype.mul = function () {
    var l = this.unary();
    for (;;) {
        if (this.isOp("*") || this.isOp("/") || this.isOp("mod")) {
            var op = this.t[this.i++].v;
            var r = this.unary();
            if (op === "*") l = { v: l.v * r.v };
            else if (op === "/") l = { v: l.v / r.v };
            else l = { v: ((l.v % r.v) + r.v) % r.v };
        } else if (this.startsOperand()) {   // implicit: 2π, 3(4), (1)(2), 2sin30
            var r2 = this.unary();
            l = { v: l.v * r2.v };
        } else return l;
    }
};
Parser.prototype.unary = function () {
    if (this.isOp("-")) { this.i++; var u = this.unary(); return { v: -u.v, pct: u.pct }; }
    if (this.isOp("+")) { this.i++; return this.unary(); }
    return this.pow();
};
Parser.prototype.pow = function () {
    var b = this.postfix();
    if (this.isOp("^")) { this.i++; var e = this.unary(); return { v: Math.pow(b.v, e.v) }; }
    return b;
};
Parser.prototype.postfix = function () {
    var x = this.primary();
    for (;;) {
        if (this.isOp("!")) { this.i++; x = { v: fact(x.v) }; }
        else if (this.isOp("%")) {
            // "%" followed by an operand is modulo (10 % 3), otherwise percent (15%)
            var nx = this.t[this.i + 1];
            if (nx && (nx.t === "n" || nx.t === "id" || (nx.t === "o" && nx.v === "("))) {
                this.i++; var r = this.postfix(); x = { v: ((x.v % r.v) + r.v) % r.v };
            } else { this.i++; x = { v: x.v / 100, pct: true }; }
        } else return x;
    }
};
Parser.prototype.args = function () {
    var a = [];
    if (this.isOp(")")) { this.i++; return a; }
    for (;;) {
        a.push(this.add().v);
        if (this.isOp(",")) { this.i++; continue; }
        if (this.isOp(")")) { this.i++; return a; }
        if (this.i >= this.t.length) return a;   // unclosed - tolerated for the live preview
        this.fail();
    }
};
Parser.prototype.primary = function () {
    var p = this.peek();
    if (!p) this.fail();
    if (p.t === "n") { this.i++; return { v: p.v }; }
    if (p.t === "o" && p.v === "(") {
        this.i++;
        var x = this.add();
        if (this.isOp(")")) this.i++;
        else if (this.i < this.t.length) this.fail();
        return { v: x.v };
    }
    if (p.t === "id") {
        this.i++;
        var id = p.v;
        if (id === "ans") return { v: typeof this.o.ans === "number" ? this.o.ans : 0 };
        if (CONSTS.hasOwnProperty(id)) return { v: CONSTS[id] };
        if (FUNCS[id]) {
            var a;
            if (this.isOp("(")) { this.i++; a = this.args(); }
            else a = [this.pow().v];               // sin 30, √9, √2^2 → √(2^2)
            return { v: callFn(id, a, this.o) };
        }
        this.fail();
    }
    this.fail();
};

function fact(n) {
    if (n < 0 || Math.floor(n) !== n) return gamma(n + 1);
    if (n > 170) return Infinity;
    var r = 1;
    for (var i = 2; i <= n; i++) r *= i;
    return r;
}
function gamma(z) {   // Lanczos
    if (z < 0.5) return Math.PI / (Math.sin(Math.PI * z) * gamma(1 - z));
    var g = 7, c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
        -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
    z -= 1;
    var x = c[0];
    for (var i = 1; i < g + 2; i++) x += c[i] / (z + i);
    var t = z + g + 0.5;
    return Math.sqrt(2 * Math.PI) * Math.pow(t, z + 0.5) * Math.exp(-t) * x;
}
function gcd(a, b) { a = Math.abs(a); b = Math.abs(b); while (b) { var t = b; b = a % b; a = t; } return a; }
function snap(x) { return Math.abs(x) < 1e-13 ? 0 : x; }

function callFn(id, a, o) {
    var x = a[0];
    if (a.length === 0) throw new Error("args");
    var k = o.deg ? Math.PI / 180 : 1;
    switch (id) {
    case "sin": return snap(Math.sin(x * k));
    case "cos": return snap(Math.cos(x * k));
    case "tan": {
        if (o.deg && Math.abs(((x % 180) + 180) % 180 - 90) < 1e-12) return NaN;
        return snap(Math.tan(x * k));
    }
    case "asin": return Math.asin(x) / k;
    case "acos": return Math.acos(x) / k;
    case "atan": return a.length > 1 ? Math.atan2(a[0], a[1]) / k : Math.atan(x) / k;
    case "sinh": return Math.sinh(x);
    case "cosh": return Math.cosh(x);
    case "tanh": return Math.tanh(x);
    case "asinh": return Math.asinh(x);
    case "acosh": return Math.acosh(x);
    case "atanh": return Math.atanh(x);
    case "ln": return Math.log(x);
    case "log": return a.length > 1 ? Math.log(a[0]) / Math.log(a[1]) : Math.log10(x);
    case "lg": return Math.log10(x);
    case "log2": return Math.log2(x);
    case "sqrt": return Math.sqrt(x);
    case "cbrt": return Math.cbrt(x);
    case "root": return a.length > 1 ? Math.pow(a[0], 1 / a[1]) : Math.sqrt(x);
    case "abs": return Math.abs(x);
    case "exp": return Math.exp(x);
    case "floor": return Math.floor(x);
    case "ceil": return Math.ceil(x);
    case "round": return a.length > 1 ? Math.round(a[0] * Math.pow(10, a[1])) / Math.pow(10, a[1]) : Math.round(x);
    case "trunc": return Math.trunc(x);
    case "sign": return Math.sign(x);
    case "min": return Math.min.apply(null, a);
    case "max": return Math.max.apply(null, a);
    case "pow": return Math.pow(a[0], a.length > 1 ? a[1] : 2);
    case "fact": return fact(x);
    case "ncr": return Math.round(fact(a[0]) / (fact(a[1]) * fact(a[0] - a[1])));
    case "npr": return Math.round(fact(a[0]) / fact(a[0] - a[1]));
    case "gcd": return a.reduce(gcd);
    case "lcm": return a.reduce(function (p, q) { return Math.abs(p * q) / gcd(p, q); });
    }
    throw new Error("fn");
}

function evalMath(text, opts) {
    var toks = tokenize(text);
    if (!toks || !toks.length) return null;
    // trailing binary operator while typing ("12+") → evaluate what is complete
    while (toks.length && toks[toks.length - 1].t === "o" && "+-*/^,(mod".indexOf(toks[toks.length - 1].v) >= 0 && toks[toks.length - 1].v !== ")")
        toks.pop();
    if (!toks.length) return null;
    var p = new Parser(toks, opts);
    var r = p.add();
    if (p.i < toks.length) throw new Error("trailing");
    return r.v;
}

// "5 km to mi", "100 usd в rub", "30c in f"
var CONV_RE = /^(.*?[0-9)πe.])\s*([^\s0-9()+*^,][^\s]*(?:\s?oz)?)\s+(?:to|in|into|в|во|->|→|=)\s+(\S+(?:\s?oz)?)\s*$/i;

function evaluate(text, opts) {
    opts = opts || {};
    var s = String(text || "").trim();
    if (!s) return { ok: false, empty: true };
    try {
        var m = CONV_RE.exec(normalize(s).replace(/\//g, "/"));
        if (m) {
            var u1 = findUnit(m[2], opts.fx), u2 = findUnit(m[3], opts.fx);
            if (u1 && u2 && u1.cat === u2.cat) {
                var a = evalMath(m[1], opts);
                if (a !== null && isFinite(a)) {
                    var v = convert(a, u1.cat, u1.id, u2.id, opts.fx);
                    if (isFinite(v)) return { ok: true, v: v, s: fmt(v), unit: u2.id, conv: true };
                }
            }
            if ((u1 && u1.cat === "currency") || (u2 && u2.cat === "currency") || /^[A-Za-z]{3}$/.test(m[3]))
                return { ok: false, needFx: !opts.fx };
        }
        var r = evalMath(s, opts);
        if (r === null || typeof r !== "number" || isNaN(r)) return { ok: false };
        if (!isFinite(r)) return { ok: false, inf: true };
        return { ok: true, v: r, s: fmt(r) };
    } catch (e) {
        return { ok: false };
    }
}

// ── formatting ───────────────────────────────────────────────────────
function clean(v) {
    if (v === 0) return 0;
    return parseFloat(v.toPrecision(12));
}
// raw: re-parseable, no group separators
function raw(v) {
    if (typeof v !== "number" || !isFinite(v)) return "";
    v = clean(v);
    var a = Math.abs(v);
    if (a !== 0 && (a >= 1e15 || a < 1e-9)) {
        var e = v.toExponential(10).replace(/\.?0+e/, "e").replace("e+", "e");
        return e;
    }
    var s = String(v);
    if (/e/.test(s)) s = v.toFixed(12).replace(/\.?0+$/, "");
    return s;
}
function group(intPart) { return intPart.replace(/\B(?=(\d{3})+(?!\d))/g, " "); }
// pretty: thin-space groups, minus sign, ×10ⁿ for exponents
function fmt(v) {
    var r = raw(v);
    if (!r) return "";
    var m = /^(-?)(\d+)(\.\d+)?(?:e(-?\d+))?$/.exec(r);
    if (!m) return r;
    var sup = { "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻" };
    var out = (m[1] ? "−" : "") + (m[4] ? m[2] : group(m[2])) + (m[3] || "");
    if (m[4]) out += "×10" + m[4].split("").map(function (ch) { return sup[ch]; }).join("");
    return out;
}
// pretty-print an expression as typed (operators → math glyphs)
function pretty(s) {
    return String(s).replace(/\*/g, "×").replace(/\//g, "÷").replace(/-/g, "−");
}
