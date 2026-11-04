#include "Strip.h"

#include "Bridge.h"
#include "Ui.h"

#include <algorithm>
#include <cmath>

namespace araso {

namespace {

const wchar_t *kStripClass = L"ArasoStrip";
constexpr UINT_PTR kFrameTimer = 1;

// macOS's measures, in points there and DIPs here: the input source indicator's capsule height
// and its gap below the caret, a cell's padding, how wide a text gets, the room around the strip
// for its shadow, the card's paper around its rows and the room under them for the footer.
constexpr float kHeight = 23, kGap = 4, kPad = 10, kMaxText = 140, kMargin = 12, kInset = 3, kFooterHeight = 16;
constexpr float kMarkSide = 11;
/// The line every text of the strip sits on: the reading's cap height (Segoe UI's, 0.7 em at
/// 13) centered in the capsule. Marks are centered on the same middle.
constexpr float kCapHeight = 13 * 0.7f;
constexpr float kBaseline = (kHeight + kCapHeight) / 2;
constexpr int kPageSize = 9;

ID2D1Factory *g_d2d = nullptr;
IDWriteFactory *g_dwrite = nullptr;
ID2D1DCRenderTarget *g_target = nullptr;
ID2D1StrokeStyle *g_round = nullptr;
IDWriteTextFormat *g_cellFormat = nullptr, *g_numberFormat = nullptr, *g_footerFormat = nullptr,
                  *g_outcomeFormat = nullptr, *g_iconFormat = nullptr;

bool HasFamily(const wchar_t *name) {
    IDWriteFontCollection *fonts = nullptr;
    if (FAILED(g_dwrite->GetSystemFontCollection(&fonts, FALSE)) || !fonts) return false;
    UINT32 index = 0;
    BOOL exists = FALSE;
    fonts->FindFamilyName(name, &index, &exists);
    fonts->Release();
    return exists != FALSE;
}

IDWriteTextFormat *MakeFormat(const wchar_t *family, float size, DWRITE_FONT_WEIGHT weight) {
    IDWriteTextFormat *format = nullptr;
    g_dwrite->CreateTextFormat(family, nullptr, weight, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size,
                               L"en-us", &format);
    if (format) format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    return format;
}

/// Direct2D and DirectWrite, made once for the host's UI thread.
bool Factories() {
    if (g_target) return true;
    if (!g_d2d && FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), nullptr,
                                           reinterpret_cast<void **>(&g_d2d)))) {
        return false;
    }
    if (!g_dwrite && FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                                reinterpret_cast<IUnknown **>(&g_dwrite)))) {
        return false;
    }
    if (!g_cellFormat) {
        // Regular, not the Mac's medium: Malgun Gothic and Yu Gothic, which Hangul and kana fall back
        // to, have no medium, and medium came out as their bold.
        const wchar_t *family = HasFamily(L"Segoe UI Variable Text") ? L"Segoe UI Variable Text" : L"Segoe UI";
        g_cellFormat = MakeFormat(family, 13, DWRITE_FONT_WEIGHT_REGULAR);
        g_numberFormat = MakeFormat(family, 10, DWRITE_FONT_WEIGHT_REGULAR);
        g_footerFormat = MakeFormat(family, 11, DWRITE_FONT_WEIGHT_REGULAR);
        g_outcomeFormat = MakeFormat(family, 12, DWRITE_FONT_WEIGHT_SEMI_BOLD);
        // The pencil and the arrow back: Windows' own icon font (Segoe MDL2 Assets on Windows 10).
        g_iconFormat = MakeFormat(HasFamily(L"Segoe Fluent Icons") ? L"Segoe Fluent Icons" : L"Segoe MDL2 Assets", 10,
                                  DWRITE_FONT_WEIGHT_REGULAR);
        if (!g_cellFormat || !g_numberFormat || !g_footerFormat || !g_outcomeFormat || !g_iconFormat) return false;
        g_iconFormat->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
        g_iconFormat->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
        // A text longer than the cell is cut with an ellipsis.
        IDWriteInlineObject *ellipsis = nullptr;
        g_dwrite->CreateEllipsisTrimmingSign(g_cellFormat, &ellipsis);
        DWRITE_TRIMMING trimming = {DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
        g_cellFormat->SetTrimming(&trimming, ellipsis);
        if (ellipsis) ellipsis->Release();
    }
    if (!g_round) {
        g_d2d->CreateStrokeStyle(D2D1::StrokeStyleProperties(D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
                                                             D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_ROUND),
                                 nullptr, 0, &g_round);
    }
    D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
    return SUCCEEDED(g_d2d->CreateDCRenderTarget(&properties, &g_target));
}

/// The locale a text is shaped in, so its Han characters take Japanese forms in a Japanese
/// candidate and Korean ones in Korean.
const wchar_t *LocaleOf(const std::wstring &text, bool japanese) {
    bool hangul = false, han = false;
    for (wchar_t ch : text) {
        if (ch >= 0x3040 && ch <= 0x30FF) return L"ja-jp";
        if ((ch >= 0xAC00 && ch <= 0xD7A3) || (ch >= 0x1100 && ch <= 0x11FF) || (ch >= 0x3130 && ch <= 0x318F)) hangul = true;
        if (ch >= 0x4E00 && ch <= 0x9FFF) han = true;
    }
    if (hangul) return L"ko-kr";
    if (han) return japanese ? L"ja-jp" : L"ko-kr";
    return L"en-us";
}

Com<IDWriteTextLayout> Layout(const std::wstring &text, IDWriteTextFormat *format, float maxWidth, bool japanese = false) {
    Com<IDWriteTextLayout> layout;
    g_dwrite->CreateTextLayout(text.c_str(), static_cast<UINT32>(text.size()), format, maxWidth, 100, layout.put());
    if (layout) layout->SetLocaleName(LocaleOf(text, japanese), DWRITE_TEXT_RANGE{0, static_cast<UINT32>(text.size())});
    return layout;
}

float WidthOf(IDWriteTextLayout *layout) {
    DWRITE_TEXT_METRICS metrics = {};
    if (!layout || FAILED(layout->GetMetrics(&metrics))) return 0;
    return std::ceil(metrics.width) + 1;
}

/// How far the first line's baseline is below the layout's top.
float BaselineOf(IDWriteTextLayout *layout) {
    DWRITE_LINE_METRICS line = {};
    UINT32 count = 0;
    if (!layout || FAILED(layout->GetLineMetrics(&line, 1, &count)) || count == 0) return 0;
    return line.baseline;
}

float NumberWidth() {
    static float width = WidthOf(Layout(L"8", g_numberFormat, 100).get());
    return width;
}

D2D1_COLOR_F Rgb(UINT32 hex, float alpha = 1) {
    return D2D1::ColorF(((hex >> 16) & 0xFF) / 255.0f, ((hex >> 8) & 0xFF) / 255.0f, (hex & 0xFF) / 255.0f, alpha);
}

D2D1_COLOR_F FromColorRef(COLORREF color) {
    return D2D1::ColorF(GetRValue(color) / 255.0f, GetGValue(color) / 255.0f, GetBValue(color) / 255.0f, 1);
}

D2D1_COLOR_F Faded(D2D1_COLOR_F color, float alpha) {
    color.a *= alpha;
    return color;
}

D2D1_COLOR_F Mix(D2D1_COLOR_F a, D2D1_COLOR_F b, float t) {
    return D2D1::ColorF(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
}

/// Araso's paper, as on the website and in the settings window: birch paper and navy ink, navy
/// paper in the dark.
struct Paper {
    D2D1_COLOR_F background, ink2, line, reset, thumb;
    float shadow;

    static Paper Current() {
        ui::Theme theme = ui::CurrentTheme();
        Paper paper;
        paper.background = theme.dark ? Rgb(0x0d213b) : Rgb(0xfaf8f4);
        paper.ink2 = theme.dark ? Rgb(0xa9b6c6) : Rgb(0x4a5b70);
        paper.line = theme.dark ? Rgb(0xf3f1ec, 0.16f) : Rgb(0xe6e1d8);
        // The capsule of a word that went back to Araso's own reading: nothing remembered any more.
        paper.reset = theme.dark ? Rgb(0x636366) : Rgb(0x6e6e73);
        paper.thumb = FromColorRef(theme.accent);
        // The strip's shadow, deeper on dark paper.
        paper.shadow = theme.dark ? 0.45f : 0.14f;
        return paper;
    }
};

/// The paper of the frame being drawn.
Paper g_paper;

/// Motion keeps out of the way of typing, and stays still when Windows is set to show no animations.
bool ReduceMotion() {
    BOOL animate = TRUE;
    SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animate, 0);
    return animate == FALSE;
}

double Now() {
    static LARGE_INTEGER frequency = [] {
        LARGE_INTEGER value;
        QueryPerformanceFrequency(&value);
        return value;
    }();
    LARGE_INTEGER counter;
    QueryPerformanceCounter(&counter);
    return static_cast<double>(counter.QuadPart) / static_cast<double>(frequency.QuadPart);
}

/// CSS's cubic-bezier(x1, y1, x2, y2) at `x`.
double Bezier(double x1, double y1, double x2, double y2, double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    auto curve = [](double a, double b, double t) { return 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t; };
    double lo = 0, hi = 1, t = x;
    for (int i = 0; i < 30; i++) {
        t = (lo + hi) / 2;
        if (curve(x1, x2, t) < x) lo = t; else hi = t;
    }
    return curve(y1, y2, t);
}

/// Fast out, gentle in: a move that is over before the next key.
double Ease(double x) { return Bezier(0.2, 0.8, 0.2, 1, x); }

/// Linear between evenly spaced `values`, over `t` from 0 to 1.
float Keyframes(std::initializer_list<float> values, const std::initializer_list<float> &times, double t) {
    const float *v = values.begin();
    const float *k = times.begin();
    size_t n = values.size();
    if (t <= k[0]) return v[0];
    for (size_t i = 1; i < n; i++) {
        if (t <= k[i]) return v[i - 1] + (v[i] - v[i - 1]) * static_cast<float>((t - k[i - 1]) / (k[i] - k[i - 1]));
    }
    return v[n - 1];
}

constexpr float kPi = 3.14159265f;

/// A soft shadow under `rect`, as the Mac's views cast (5 pt blur, 3 pt down): rings fading out.
void Shadow(ID2D1RenderTarget *target, ID2D1SolidColorBrush *brush, D2D1_RECT_F rect, float radius, float opacity) {
    if (opacity <= 0) return;
    for (int ring = 5; ring >= 0; ring--) {
        float grow = static_cast<float>(ring);
        D2D1_RECT_F shadow = {rect.left - grow, rect.top + 3 - grow, rect.right + grow, rect.bottom + 3 + grow};
        D2D1_COLOR_F black = D2D1::ColorF(0, 0, 0, opacity * 0.2f);
        brush->SetColor(&black);
        target->FillRoundedRectangle(D2D1::RoundedRect(shadow, radius + grow, radius + grow), brush);
    }
}

}  // namespace

// MARK: - Motion

float StripWindow::Motion::At(double now) const {
    if (duration <= 0 || now >= start + duration) return now < start ? from : to;
    if (now <= start) return from;
    double t = (now - start) / duration;
    return from + (to - from) * static_cast<float>(ease ? Ease(t) : t);
}

void StripWindow::Motion::Go(float value, double now, double seconds, double delay, bool eased) {
    from = At(now);
    to = value;
    start = now + delay;
    duration = ReduceMotion() ? 0 : seconds;
    ease = eased;
}

// MARK: - What is shown

StripWindow::Cell StripWindow::MakeCell(const std::wstring &text, int number, Mark mark, bool japanese) const {
    Cell cell;
    cell.text = text;
    cell.number = number;
    cell.mark = mark;
    cell.layout = Layout(text, g_cellFormat, kMaxText, japanese);
    cell.textWidth = std::min(WidthOf(cell.layout.get()), kMaxText);
    cell.textX = kPad;
    if (number > 0) {
        cell.numberLayout = Layout(std::to_wstring(number), g_numberFormat, 100);
        cell.textX += NumberWidth() + 3;
    }
    float width = cell.textX + cell.textWidth + (mark != Mark::none ? 5 + kMarkSide : 0) + kPad;
    cell.frame = D2D1::RectF(0, 0, width, kHeight);
    return cell;
}

/// Wide enough for every candidate in `texts`, whichever page it is on, and for `footer`, the
/// widest the footer gets (the last page's count).
float StripWindow::CardWidth(const std::vector<std::wstring> &texts, const std::wstring &footer, bool japanese) {
    if (texts == measuredTexts_ && footer == measuredFooter_) return measuredWidth_;
    float widest = 0;
    for (const auto &text : texts) {
        float width = std::min(WidthOf(Layout(text, g_cellFormat, kMaxText, japanese).get()), kMaxText);
        widest = std::max(widest, kPad + NumberWidth() + 3 + width + kPad);
    }
    float footerWidth = WidthOf(Layout(footer, g_footerFormat, 1000, japanese).get()) + kPad * 2;
    measuredTexts_ = texts;
    measuredFooter_ = footer;
    measuredWidth_ = std::ceil(std::max(widest, footerWidth)) + kInset * 2;
    return measuredWidth_;
}

void StripWindow::ShowReadings(const std::vector<std::wstring> &texts, const std::vector<Mark> &marks, int selected,
                               const RECT &word, std::function<void(int)> pick) {
    if (texts.empty() || word.bottom <= word.top || !Factories()) return Hide(true);
    pick_ = std::move(pick);
    choose_ = nullptr;
    selected = std::max(0, std::min(selected, static_cast<int>(texts.size()) - 1));
    if (Up() && !settling_ && mode_ == Mode::list && texts == texts_ && marks == marks_) {
        Select(selected);
        return;
    }
    settling_ = false;
    pageStart_ = 0;
    texts_ = texts;
    marks_ = marks;
    std::vector<Cell> cells;
    for (size_t i = 0; i < texts.size(); i++) {
        cells.push_back(MakeCell(texts[i], 0, i < marks.size() ? marks[i] : Mark::none, false));
    }
    float width = 0;
    for (const auto &cell : cells) width = std::max(width, cell.frame.right - cell.frame.left);
    int rows = static_cast<int>(cells.size());
    footer_.clear();
    footerLayout_ = Com<IDWriteTextLayout>();
    Build(std::move(cells), Mode::list, std::ceil(width) + kInset * 2, rows, selected, word, 0);
}

void StripWindow::ShowCandidates(const std::vector<std::wstring> &texts, int selected, const std::wstring &reading,
                                 const RECT &clause, std::function<void(int)> choose) {
    if (texts.empty() || clause.bottom <= clause.top || !Factories()) return Hide(true);
    choose_ = std::move(choose);
    pick_ = nullptr;
    selected = std::max(0, std::min(selected, static_cast<int>(texts.size()) - 1));
    int page = selected / kPageSize;
    bool sameList = Up() && !settling_ && mode_ == Mode::card && texts == texts_ && reading == reading_;
    if (sameList && page == page_) {
        Select(selected % kPageSize);
        return;
    }
    int turn = sameList ? (page > page_ ? 1 : -1) : 0;
    settling_ = false;
    texts_ = texts;
    reading_ = reading;
    marks_.clear();
    page_ = page;
    pageStart_ = page * kPageSize;
    // A text replacement's phrases are Korean or English; anything else here is Japanese.
    bool japanese = std::wstring(LocaleOf(reading, true)) == L"ja-jp";
    int count = static_cast<int>(texts.size());
    int pages = (count + kPageSize - 1) / kPageSize;
    auto footer = [&](int p) {
        return pages > 1 ? reading + L" · " + std::to_wstring(p + 1) + L"/" + std::to_wstring(pages) : reading;
    };
    footer_ = footer(page);
    footerLayout_ = Layout(footer_, g_footerFormat, 1000, japanese);
    std::vector<Cell> cells;
    for (int i = pageStart_; i < std::min(pageStart_ + kPageSize, count); i++) {
        cells.push_back(MakeCell(texts[i], i - pageStart_ + 1, Mark::none, japanese));
    }
    Build(std::move(cells), Mode::card, CardWidth(texts, footer(pages - 1), japanese), std::min(kPageSize, count),
          selected % kPageSize, clause, turn);
}

/// The readings in a row or the candidates in a card, `selected` on the thumb, the first text
/// under the word's first letter (the clause's, for candidates). A page turned (`turn`, +1
/// forward) keeps the card where it is and brings the next page up into it (the one before,
/// down); a new strip or card comes down 2 DIPs as it shows (up, when it is above the word).
void StripWindow::Build(std::vector<Cell> cells, Mode mode, float cardWidth, int rows, int selected, const RECT &word,
                        int turn) {
    bool wasUp = Up();
    float scale = dpi_ / 96.0f;
    POINT oldStrip = {origin_.x + static_cast<LONG>(std::lround(strip_.left * scale)),
                      origin_.y + static_cast<LONG>(std::lround(strip_.top * scale))};

    WNDCLASSEXW cls = {sizeof cls};
    if (!GetClassInfoExW(GetModuleHandleW(nullptr), kStripClass, &cls)) {
        cls.lpfnWndProc = Proc;
        cls.hInstance = GetModuleHandleW(nullptr);
        cls.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        cls.lpszClassName = kStripClass;
        RegisterClassExW(&cls);
    }
    if (!window_) {
        window_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED, kStripClass, L"",
                                  WS_POPUP, 0, 0, 1, 1, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
        if (!window_) return;
        SetWindowLongPtrW(window_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    }
    Clickable(true);
    dpi_ = ui::DpiAt(word);
    scale = dpi_ / 96.0f;

    D2D1_SIZE_F size;
    if (mode == Mode::row) {
        float x = 0;
        for (auto &cell : cells) {
            float width = cell.frame.right - cell.frame.left;
            cell.frame = D2D1::RectF(x, 0, x + width, kHeight);
            x += width;
        }
        size = D2D1::SizeF(std::ceil(x), kHeight);
        inside_ = D2D1::RectF(0, 0, size.width, kHeight);
    } else {
        // The rows inside the paper's inset, cut at its edge, so a page turned slides in under it.
        inside_ = D2D1::RectF(kInset, kInset, cardWidth - kInset, kInset + rows * kHeight);
        for (size_t i = 0; i < cells.size(); i++) {
            float top = static_cast<float>(i) * kHeight;
            cells[i].frame = D2D1::RectF(0, top, inside_.right - inside_.left, top + kHeight);
        }
        size = D2D1::SizeF(cardWidth, inside_.bottom + (mode == Mode::card ? kFooterHeight : 0) + kInset);
    }
    cells_ = std::move(cells);
    mode_ = mode;
    selected_ = std::max(0, std::min(selected, static_cast<int>(cells_.size()) - 1));
    strip_ = D2D1::RectF(kMargin, kMargin, kMargin + size.width, kMargin + size.height);
    size_ = {static_cast<LONG>(std::ceil((size.width + kMargin * 2) * scale)),
             static_cast<LONG>(std::ceil((size.height + kMargin * 2) * scale))};

    // Just under the word's line, the first text under its first letter, kept on screen; above
    // the line near the bottom of the screen.
    SIZE pixels = {static_cast<LONG>(std::ceil(size.width * scale)), static_cast<LONG>(std::ceil(size.height * scale))};
    float indent = inside_.left + (cells_.empty() ? kPad : cells_.front().textX);
    RECT work = ui::WorkAreaAt(word);
    POINT strip = {word.left - static_cast<LONG>(std::lround(indent * scale)),
                   word.bottom + static_cast<LONG>(std::lround(kGap * scale))};
    if (strip.y + pixels.cy > work.bottom) strip.y = word.top - static_cast<LONG>(std::lround(kGap * scale)) - pixels.cy;
    strip.x = std::max(work.left, std::min(strip.x, work.right - pixels.cx));
    strip.y = std::max(work.top, std::min(strip.y, work.bottom - pixels.cy));
    if (turn != 0 && wasUp) strip = oldStrip;
    above_ = strip.y < word.top;
    word_ = word;
    origin_ = {strip.x - static_cast<LONG>(std::lround(kMargin * scale)),
               strip.y - static_cast<LONG>(std::lround(kMargin * scale))};

    double now = Now();
    const D2D1_RECT_F &thumb = cells_[selected_].frame;
    thumbX_.Set(thumb.left);
    thumbY_.Set(thumb.top);
    thumbWidth_.Set(thumb.right - thumb.left);
    alpha_.Set(1);
    pageAlpha_.Set(1);
    pageSlide_.Set(0);
    appear_.Set(1);
    slide_.Set(0);
    travel_.Set(0);
    gray_.Set(0);
    if (turn != 0 && wasUp) {
        pageAlpha_.Set(0);
        pageAlpha_.Go(1, now, 0.14);
        pageSlide_.Set(14.0f * turn);
        pageSlide_.Go(0, now, 0.14);
    } else if (!wasUp) {
        appear_.Set(0);
        appear_.Go(1, now, 0.12);
        slide_.Set(above_ ? 2.0f : -2.0f);
        slide_.Go(0, now, 0.12);
    }
    shown_ = true;
    hiding_ = false;
    Render(now);
    ShowWindow(window_, SW_SHOWNOACTIVATE);
    SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    Start();
}

/// The next switch or candidate: the thumb moves to it.
void StripWindow::Select(int index) {
    if (index < 0 || index >= static_cast<int>(cells_.size())) return;
    selected_ = index;
    double now = Now();
    const D2D1_RECT_F &frame = cells_[index].frame;
    thumbX_.Go(frame.left, now, 0.12);
    thumbY_.Go(frame.top, now, 0.12);
    thumbWidth_.Go(frame.right - frame.left, now, 0.12);
    Start();
}

void StripWindow::Hide(bool force) {
    if (!shown_ || hiding_ || (!force && settling_)) return;
    hiding_ = true;
    settling_ = false;
    alpha_.Go(0, Now(), 0.1, 0, false);
    Start();
}

/// The correction the dictionary just took: the paper closes onto the chosen reading, whose
/// capsule moves under the word's first letter and says what happened, a pencil and "Noted" after
/// the first correction, the check drawing itself and "Learned" once learned for good, the arrow
/// back and "Reset" on gray when a switch back to Araso's own reading forgot the word.
void StripWindow::Settle(const std::wstring &text, const std::string &learning, const RECT &word) {
    if (!Factories()) return;
    bool hasWord = word.bottom > word.top;
    int index;
    RECT under = word;
    if (Up() && !settling_ && mode_ == Mode::list && selected_ < static_cast<int>(cells_.size())) {
        index = selected_;
        under = word_;
        hasWord = true;
    } else {
        if (!hasWord) return;
        texts_.clear();
        marks_.clear();
        Build({MakeCell(text, 0, Mark::none, false)}, Mode::row, 0, 0, 0, word, 0);
        index = 0;
    }
    if (!window_) return;
    double now = Now();
    float scale = dpi_ / 96.0f;
    learning_ = learning;
    settling_ = true;
    settleStart_ = now;
    settleCell_ = index;
    texts_.clear(); // a strip shown next is built anew
    Clickable(false);

    // Room after the text for what the correction did: the mark's place, then the word.
    Cell &cell = cells_[index];
    const D2D1_RECT_F start = cell.frame;
    const char *said = learning == "once" ? "Noted" : learning == "forGood" ? "Learned" : "Reset";
    outcome_ = Layout(L(said), g_outcomeFormat, 1000);
    markX_ = cell.textX + cell.textWidth + 5;
    outcomeX_ = markX_ + kMarkSide + 6;
    float width = outcomeX_ + WidthOf(outcome_.get()) + kPad;

    // Where the capsule goes: under the word's first letter, as wide as what it says. The window
    // grows to cover it at once, nothing moving on screen, so the strip can travel there.
    float stripLeft = origin_.x + strip_.left * scale, stripTop = origin_.y + strip_.top * scale;
    float from = stripLeft + start.left * scale;
    if (mode_ == Mode::list) {
        // The card itself becomes the capsule, in one move: its paper and the thumb land on the
        // same frame, the other readings gone early, and the capsule takes over the shadow as the
        // paper goes.
        float cardWidth = strip_.right - strip_.left, cardHeight = strip_.bottom - strip_.top;
        RECT work = ui::WorkAreaAt(under);
        float to = std::max(static_cast<float>(work.left),
                            std::min(under.left - kPad * scale, static_cast<float>(work.right) - width * scale));
        float left = std::min(stripLeft, to) - kMargin * scale;
        float right = std::max(stripLeft + cardWidth * scale, to + width * scale) + kMargin * scale;
        POINT origin = {static_cast<LONG>(std::floor(left)), origin_.y};
        strip_.left = (stripLeft - origin.x) / scale;
        strip_.right = strip_.left + std::max(cardWidth, (to - stripLeft) / scale + width);
        origin_ = origin;
        size_ = {static_cast<LONG>(std::ceil(right - origin.x)), size_.cy};
        const float capsuleLeft = (to - stripLeft) / scale, capsuleTop = above_ ? cardHeight - kHeight : 0;
        const double move = 0.26;
        trackLeft_.Set(0);
        trackLeft_.Go(capsuleLeft, now, move);
        trackRight_.Set(cardWidth);
        trackRight_.Go(capsuleLeft + width, now, move);
        trackTop_.Set(0);
        trackTop_.Go(capsuleTop, now, move);
        trackBottom_.Set(cardHeight);
        trackBottom_.Go(capsuleTop + kHeight, now, move);
        trackRadius_.Set(kInset + kHeight / 2);
        trackRadius_.Go(kHeight / 2, now, move);
        trackAlpha_.Set(1);
        trackAlpha_.Go(0, now, 0.08, 0.24);
        othersAlpha_.Set(1);
        othersAlpha_.Go(0, now, 0.1);
        travel_.Set(0);
        thumbX_.Set(start.left);
        thumbY_.Set(start.top);
        thumbWidth_.Set(start.right - start.left);
        thumbX_.Go(capsuleLeft - inside_.left, now, move);
        thumbY_.Go(capsuleTop - inside_.top, now, move);
        thumbWidth_.Go(width, now, move);
        gray_.Set(0);
        if (learning == "forgot") gray_.Go(1, now, move);
        settleSay_ = 0.08;
        outcomeAlpha_.Set(0);
        outcomeAlpha_.Go(1, now, 0.2, 0.08);
        alpha_.Set(1);
        alpha_.Go(0, now, 0.25, 1.9, false);
        Render(now);
        Start();
        return;
    }
    float to = from;
    if (hasWord) {
        RECT work = ui::WorkAreaAt(under);
        to = std::max(static_cast<float>(work.left),
                      std::min(under.left - kPad * scale, static_cast<float>(work.right) - width * scale));
    }
    float trackWidth = strip_.right - strip_.left;
    float stripWidth = std::max(trackWidth, start.left + width);
    float left = std::min(stripLeft, to - start.left * scale) - kMargin * scale;
    float right = std::max(stripLeft + stripWidth * scale, to + width * scale) + kMargin * scale;
    POINT origin = {static_cast<LONG>(std::floor(left)), static_cast<LONG>(std::floor(stripTop - kMargin * scale))};
    strip_.left = (stripLeft - origin.x) / scale;
    strip_.top = (stripTop - origin.y) / scale;
    strip_.right = strip_.left + stripWidth;
    strip_.bottom = strip_.top + kHeight;
    origin_ = origin;
    size_ = {static_cast<LONG>(std::ceil(right - origin.x)), static_cast<LONG>(std::ceil((kHeight + kMargin * 2) * scale))};

    // The paper closes onto the chosen reading and goes with the others; the capsule takes over
    // its shadow. Then it moves under the word and says it.
    thumbX_.Set(start.left);
    thumbY_.Set(0);
    thumbWidth_.Set(start.right - start.left);
    trackLeft_.Set(0);
    trackLeft_.Go(start.left, now, 0.15);
    trackRight_.Set(trackWidth);
    trackRight_.Go(start.right, now, 0.15);
    trackTop_.Set(0);
    trackBottom_.Set(kHeight);
    trackRadius_.Set(kHeight / 2);
    trackAlpha_.Set(1);
    trackAlpha_.Go(0, now, 0.15);
    othersAlpha_.Set(1);
    othersAlpha_.Go(0, now, 0.15);
    settleSay_ = 0.24;
    travel_.Set(0);
    travel_.Go((to - from) / scale, now, 0.22, 0.16);
    thumbWidth_.Go(width, now, 0.22, 0.16);
    gray_.Set(0);
    if (learning == "forgot") gray_.Go(1, now, 0.22, 0.16);
    outcomeAlpha_.Set(0);
    outcomeAlpha_.Go(1, now, 0.2, 0.24);
    alpha_.Set(1);
    alpha_.Go(0, now, 0.25, 1.9, false);
    Render(now);
    Start();
}

// MARK: - Drawing

void StripWindow::Start() {
    if (window_) SetTimer(window_, kFrameTimer, 16, nullptr);
}

void StripWindow::Frame() {
    double now = Now();
    if (hiding_ && !alpha_.Moving(now)) {
        KillTimer(window_, kFrameTimer);
        ShowWindow(window_, SW_HIDE);
        shown_ = hiding_ = false;
        mode_ = Mode::none;
        texts_.clear();
        return;
    }
    if (settling_ && now >= settleStart_ + 2.15) {
        KillTimer(window_, kFrameTimer);
        ShowWindow(window_, SW_HIDE);
        shown_ = settling_ = false;
        mode_ = Mode::none;
        return;
    }
    Render(now);
    bool moving = settling_ || hiding_;
    for (const Motion *motion : {&thumbX_, &thumbY_, &thumbWidth_, &appear_, &slide_, &pageAlpha_, &pageSlide_, &alpha_}) {
        moving = moving || motion->Moving(now);
    }
    if (!moving) KillTimer(window_, kFrameTimer);
}

void StripWindow::Render(double now) {
    if (!window_ || !g_target || size_.cx <= 0 || size_.cy <= 0) return;
    HDC screen = GetDC(nullptr);
    if (!dc_) dc_ = CreateCompatibleDC(screen);
    if (!bitmap_ || bitmapSize_.cx != size_.cx || bitmapSize_.cy != size_.cy) {
        if (bitmap_) {
            SelectObject(dc_, oldBitmap_);
            DeleteObject(bitmap_);
        }
        BITMAPINFO info = {};
        info.bmiHeader.biSize = sizeof info.bmiHeader;
        info.bmiHeader.biWidth = size_.cx;
        info.bmiHeader.biHeight = -size_.cy;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        void *bits = nullptr;
        bitmap_ = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
        oldBitmap_ = SelectObject(dc_, bitmap_);
        bitmapSize_ = size_;
    }
    RECT bounds = {0, 0, size_.cx, size_.cy};
    ID2D1DCRenderTarget *target = g_target;
    if (FAILED(target->BindDC(dc_, &bounds))) {
        ReleaseDC(nullptr, screen);
        return;
    }
    target->SetDpi(static_cast<float>(dpi_), static_cast<float>(dpi_));
    target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    g_paper = Paper::Current();
    const Paper &paper = g_paper;
    Com<ID2D1SolidColorBrush> brush;
    target->BeginDraw();
    target->Clear(D2D1::ColorF(0, 0, 0, 0));
    target->CreateSolidColorBrush(paper.background, brush.put());
    if (brush) {
        float width = strip_.right - strip_.left, height = strip_.bottom - strip_.top;
        D2D1::Matrix3x2F base = D2D1::Matrix3x2F::Translation(strip_.left + travel_.At(now), strip_.top + slide_.At(now));
        target->SetTransform(base);

        // The paper: the track, rounded about the thumb (the card's further out by its inset).
        float radius = mode_ != Mode::row ? kInset + kHeight / 2 : kHeight / 2;
        D2D1_RECT_F track = D2D1::RectF(0, 0, width, height);
        float trackAlpha = 1;
        if (settling_) {
            track = D2D1::RectF(trackLeft_.At(now), trackTop_.At(now), trackRight_.At(now), trackBottom_.At(now));
            radius = trackRadius_.At(now);
            trackAlpha = trackAlpha_.At(now);
        }
        if (trackAlpha > 0) {
            Shadow(target, brush.get(), track, radius, paper.shadow * trackAlpha);
            D2D1_COLOR_F fill = Faded(paper.background, trackAlpha), line = Faded(paper.line, trackAlpha);
            brush->SetColor(&fill);
            target->FillRoundedRectangle(D2D1::RoundedRect(track, radius, radius), brush.get());
            brush->SetColor(&line);
            D2D1_RECT_F edge = {track.left + 0.5f, track.top + 0.5f, track.right - 0.5f, track.bottom - 0.5f};
            target->DrawRoundedRectangle(D2D1::RoundedRect(edge, radius - 0.5f, radius - 0.5f), brush.get(), 1);
        }

        // The page: the thumb and the cells, cut at the card's inside so a page turned slides in.
        float pageAlpha = pageAlpha_.At(now);
        // A card folding into its capsule leaves its inside on the way.
        bool clipped = mode_ != Mode::row && !settling_;
        if (clipped) target->PushAxisAlignedClip(inside_, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        target->SetTransform(D2D1::Matrix3x2F::Translation(inside_.left, inside_.top + pageSlide_.At(now)) * base);
        D2D1_RECT_F thumb = D2D1::RectF(thumbX_.At(now), thumbY_.At(now), thumbX_.At(now) + thumbWidth_.At(now),
                                        thumbY_.At(now) + kHeight);
        if (settling_) Shadow(target, brush.get(), thumb, kHeight / 2, paper.shadow * (1 - trackAlpha));
        D2D1_COLOR_F thumbColor = Faded(Mix(paper.thumb, paper.reset, gray_.At(now)), pageAlpha);
        brush->SetColor(&thumbColor);
        target->FillRoundedRectangle(D2D1::RoundedRect(thumb, kHeight / 2, kHeight / 2), brush.get());
        for (size_t i = 0; i < cells_.size(); i++) {
            bool settled = settling_ && static_cast<int>(i) == settleCell_;
            float alpha = pageAlpha * (settling_ && !settled ? othersAlpha_.At(now) : 1);
            D2D1_MATRIX_3X2_F page;
            target->GetTransform(&page);
            if (settled && mode_ == Mode::list) {
                // The chosen reading rides on the thumb.
                target->SetTransform(D2D1::Matrix3x2F::Translation(thumb.left - cells_[i].frame.left, thumb.top - cells_[i].frame.top) *
                                     *D2D1::Matrix3x2F::ReinterpretBaseType(&page));
            }
            DrawCell(target, brush.get(), cells_[i], static_cast<int>(i) == selected_, alpha, settled, now);
            target->SetTransform(page);
        }
        target->SetTransform(base);
        if (clipped) target->PopAxisAlignedClip();
        if (mode_ == Mode::card) {
            // The reading and the page under the rows.
            if (footerLayout_) {
                D2D1_COLOR_F ink = Faded(paper.ink2, 0.85f);
                brush->SetColor(&ink);
                float y = kBaseline + inside_.bottom - 4 - BaselineOf(footerLayout_.get());
                target->DrawTextLayout(D2D1::Point2F(kInset + kPad, y), footerLayout_.get(), brush.get());
            }
        }
    }
    HRESULT drawn = target->EndDraw();
    target->SetTransform(D2D1::Matrix3x2F::Identity());
    if (drawn == static_cast<HRESULT>(D2DERR_RECREATE_TARGET)) {
        g_target->Release();
        g_target = nullptr;
    }
    POINT source = {0, 0};
    float alpha = std::max(0.0f, std::min(1.0f, alpha_.At(now) * appear_.At(now)));
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, static_cast<BYTE>(std::lround(alpha * 255)), AC_SRC_ALPHA};
    UpdateLayeredWindow(window_, screen, &origin_, &size_, dc_, &source, 0, &blend, ULW_ALPHA);
    ReleaseDC(nullptr, screen);
}

/// One reading or candidate: its number (candidates), its text, its mark (readings), white on the
/// thumb and the paper's ink beside it. The settled one says what the correction did.
void StripWindow::DrawCell(ID2D1RenderTarget *target, ID2D1SolidColorBrush *brush, const Cell &cell, bool on,
                           float alpha, bool settled, double now) {
    if (alpha <= 0) return;
    const Paper &paper = g_paper;
    D2D1_MATRIX_3X2_F page;
    target->GetTransform(&page);
    D2D1::Matrix3x2F at = D2D1::Matrix3x2F::Translation(cell.frame.left, cell.frame.top) * *D2D1::Matrix3x2F::ReinterpretBaseType(&page);
    target->SetTransform(at);
    on = on || settled;
    D2D1_COLOR_F white = D2D1::ColorF(1, 1, 1, alpha);
    D2D1_COLOR_F ink = on ? white : Faded(paper.ink2, alpha);
    if (cell.numberLayout) {
        D2D1_COLOR_F number = Faded(ink, 0.72f);
        brush->SetColor(&number);
        target->DrawTextLayout(D2D1::Point2F(kPad, kBaseline - BaselineOf(cell.numberLayout.get())), cell.numberLayout.get(), brush);
    }
    brush->SetColor(&ink);
    target->DrawTextLayout(D2D1::Point2F(cell.textX, kBaseline - BaselineOf(cell.layout.get())), cell.layout.get(), brush,
                           D2D1_DRAW_TEXT_OPTIONS_CLIP);

    // The mark: a check where the dictionary remembers the reading, a pencil where it was
    // corrected once; on the settled one, what the correction did, moving about its center.
    Glyph glyph = cell.mark == Mark::remembered ? Glyph::check : cell.mark == Mark::once ? Glyph::pencil : Glyph::none;
    float scale = 1, turn = 0, opacity = 1, drawn = 1;
    if (settled) {
        double t = now - (settleStart_ + settleSay_);
        if (ReduceMotion() && t >= 0) t = 10;
        if (t >= 0) {
            Glyph before = glyph;
            auto popIn = [&](double s) {
                scale = Keyframes({0.4f, 1.15f, 1}, {0, 0.6f, 1}, s / 0.22);
                opacity = static_cast<float>(std::min(1.0, s / 0.12));
            };
            if (learning_ == "once") {
                glyph = Glyph::pencil;
                if (before != Glyph::pencil) popIn(t);
                // The pencil writes: a quick wobble about its point.
                double w = (t - 0.1) / 0.45;
                if (w > 0 && w < 1) turn = -Keyframes({0, 0.3f, -0.18f, 0.07f, 0}, {0, 0.25f, 0.5f, 0.75f, 1}, w) * 180 / kPi;
            } else if (learning_ == "forGood") {
                if (before == Glyph::pencil && t < 0.12) {
                    // The pencil of the first correction makes way.
                    scale = 1 - 0.6f * static_cast<float>(t / 0.12);
                    opacity = 1 - static_cast<float>(t / 0.12);
                } else {
                    // The check draws itself, the short stroke then the long one.
                    glyph = Glyph::check;
                    double since = t - (before == Glyph::pencil ? 0.12 : 0);
                    drawn = static_cast<float>(Bezier(0, 0, 0.58, 1, since / 0.3));
                }
            } else {
                // The arrow back turns once, as it points.
                glyph = Glyph::back;
                popIn(t);
                turn = static_cast<float>(1.8 * 180 * (1 - Bezier(0.3, 0.9, 0.3, 1, t / 0.5)));
            }
        }
        if (outcome_) {
            D2D1_COLOR_F said = D2D1::ColorF(1, 1, 1, alpha * outcomeAlpha_.At(now));
            brush->SetColor(&said);
            target->DrawTextLayout(D2D1::Point2F(outcomeX_, kBaseline - BaselineOf(outcome_.get())), outcome_.get(), brush);
        }
    }
    if (glyph != Glyph::none && opacity > 0) {
        float x = settled ? markX_ : cell.textX + cell.textWidth + 5;
        float y = kBaseline - kCapHeight / 2 - kMarkSide / 2;
        D2D1_POINT_2F center = D2D1::Point2F(x + kMarkSide / 2, y + kMarkSide / 2);
        target->SetTransform(D2D1::Matrix3x2F::Scale(scale, scale, center) * D2D1::Matrix3x2F::Rotation(turn, center) * at);
        D2D1_COLOR_F color = on ? white : cell.mark == Mark::remembered ? Faded(paper.thumb, alpha) : ink;
        color.a *= opacity;
        brush->SetColor(&color);
        if (glyph == Glyph::check) {
            // The Mac's stroke, in its 11-point square.
            D2D1_POINT_2F p[3] = {{x + 1.6f, y + 5.4f}, {x + 4.4f, y + 8.4f}, {x + 9.6f, y + 2.1f}};
            float first = std::hypot(p[1].x - p[0].x, p[1].y - p[0].y), second = std::hypot(p[2].x - p[1].x, p[2].y - p[1].y);
            float length = drawn * (first + second);
            Com<ID2D1PathGeometry> path;
            Com<ID2D1GeometrySink> sink;
            if (length > 0.01f && SUCCEEDED(g_d2d->CreatePathGeometry(path.put())) && SUCCEEDED(path->Open(sink.put()))) {
                sink->BeginFigure(p[0], D2D1_FIGURE_BEGIN_HOLLOW);
                if (length <= first) {
                    float k = length / first;
                    sink->AddLine(D2D1::Point2F(p[0].x + (p[1].x - p[0].x) * k, p[0].y + (p[1].y - p[0].y) * k));
                } else {
                    float k = (length - first) / second;
                    sink->AddLine(p[1]);
                    sink->AddLine(D2D1::Point2F(p[1].x + (p[2].x - p[1].x) * k, p[1].y + (p[2].y - p[1].y) * k));
                }
                sink->EndFigure(D2D1_FIGURE_END_OPEN);
                sink->Close();
                target->DrawGeometry(path.get(), brush, 1.9f, g_round);
            }
        } else {
            // Edit (the pencil) and Undo (the arrow back) in Windows' icon font.
            const wchar_t *icon = glyph == Glyph::pencil ? L"\xE70F" : L"\xE7A7";
            target->DrawText(icon, 1, g_iconFormat, D2D1::RectF(x - 2, y - 2, x + kMarkSide + 2, y + kMarkSide + 2), brush);
        }
    }
    target->SetTransform(page);
}

// MARK: - Clicks

void StripWindow::Clickable(bool clickable) {
    if (!window_) return;
    LONG_PTR style = GetWindowLongPtrW(window_, GWL_EXSTYLE);
    LONG_PTR want = clickable ? style & ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT) : style | WS_EX_TRANSPARENT;
    if (want != style) SetWindowLongPtrW(window_, GWL_EXSTYLE, want);
}

/// `x`, `y` in the window's pixels: on a reading or a candidate, or where nothing is.
void StripWindow::Click(int x, int y) {
    if (settling_ || hiding_) return;
    float scale = dpi_ / 96.0f;
    float px = x / scale - strip_.left - inside_.left, py = y / scale - strip_.top - inside_.top;
    for (size_t i = 0; i < cells_.size(); i++) {
        const D2D1_RECT_F &frame = cells_[i].frame;
        if (px < frame.left || px >= frame.right || py < frame.top || py >= frame.bottom) continue;
        if (mode_ == Mode::card && choose_) {
            auto choose = choose_;
            choose(pageStart_ + static_cast<int>(i));
        } else if (mode_ == Mode::list && pick_) {
            auto pick = pick_;
            pick(static_cast<int>(i));
        }
        return;
    }
}

LRESULT CALLBACK StripWindow::Proc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    auto *self = reinterpret_cast<StripWindow *>(GetWindowLongPtrW(window, GWLP_USERDATA));
    switch (message) {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_LBUTTONDOWN:
        if (self) self->Click(static_cast<short>(LOWORD(lParam)), static_cast<short>(HIWORD(lParam)));
        return 0;
    case WM_TIMER:
        if (self && wParam == kFrameTimer) self->Frame();
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

}  // namespace araso
