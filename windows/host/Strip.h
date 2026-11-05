// The switch key's readings in a card under the word, the kana→kanji candidates in a card under
// the clause, and what a correction did (StripHUD on macOS, Sources/Araso/CaretPanel.swift): the
// blue capsule of the input source indicator as the thumb on what's on screen, the others on
// Araso's paper beside it or below it, each as it would go in. Drawn with Direct2D and DirectWrite
// into a layered window that never takes the focus; each move is a few frames on a timer.
#pragma once

#include "../common/Common.h"

#include <d2d1.h>
#include <dwrite.h>

#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace araso {

/// A COM pointer that releases what it holds.
template <class T>
class Com {
public:
    Com() = default;
    Com(const Com &other) : p_(other.p_) { if (p_) p_->AddRef(); }
    Com &operator=(const Com &other) {
        if (other.p_) other.p_->AddRef();
        if (p_) p_->Release();
        p_ = other.p_;
        return *this;
    }
    ~Com() { if (p_) p_->Release(); }
    T *get() const { return p_; }
    T *operator->() const { return p_; }
    explicit operator bool() const { return p_ != nullptr; }
    /// For a function that hands one out: what was held is released first.
    T **put() {
        if (p_) p_->Release();
        p_ = nullptr;
        return &p_;
    }

private:
    T *p_ = nullptr;
};

class StripWindow {
public:
    /// What the dictionary knows about a reading, after it in the strip.
    enum class Mark { none, remembered, once };

    /// The readings in a card under `word` (screen pixels), `selected` on the thumb, the first
    /// under the word's first letter, each with its language in its own script (`tags`: EN, KO, JA,
    /// MIX), numbered when the digits pick them; a click on another reading calls `pick` with its index.
    void ShowReadings(const std::vector<std::wstring> &texts, const std::vector<Mark> &marks,
                      const std::vector<std::string> &tags, bool numbered, int selected, const RECT &word,
                      std::function<void(int)> pick);
    /// The long press's guesses in a card under `word`, numbered, what each `changed` (UTF-16 units
    /// of its text) colored with a wave under it; a click calls `pick` with its index.
    void ShowGuesses(const std::vector<std::wstring> &texts, const std::vector<std::pair<int, int>> &changed, int selected,
                     const RECT &word, std::function<void(int)> pick);
    /// The candidates in a card of nine rows a page, numbered for the digits, under `clause`;
    /// `reading` and the page under them. As wide as the widest candidate on any page; a page
    /// turned comes up from below (down, going back). A click calls `choose` with the index in
    /// the whole list.
    void ShowCandidates(const std::vector<std::wstring> &texts, int selected, const std::wstring &reading,
                        const RECT &clause, std::function<void(int)> choose);
    /// The correction the dictionary just took (`learning`: "once", "forGood" or "forgot"): the
    /// readings' card becomes the chosen reading's capsule, under the word's first letter, and says
    /// what happened. Without a card up, the capsule shows `text` on its own. `learning` "note":
    /// only `text`, for a moment, whatever is up; "nothing": the same on gray, as nothing was done.
    void Settle(const std::wstring &text, const std::string &learning, const RECT &word);
    /// Puts the strip away; one saying what a correction did stays its moment unless `force`d.
    void Hide(bool force = false);

private:
    /// `row`: a capsule on its own; `card`: the candidates; `list`: the readings.
    enum class Mode { none, row, card, list };
    enum class Glyph { none, check, pencil, back };

    struct Cell {
        std::wstring text;
        int number = 0; // 1–9 on a card's page, 0 on the strip
        Mark mark = Mark::none;
        /// What a guess changed, in UTF-16 units of `text`.
        int changedStart = 0, changedEnd = 0;
        Com<IDWriteTextLayout> layout;
        Com<IDWriteTextLayout> numberLayout;
        float textX = 0, textWidth = 0;
        /// Where the list's marks stand, past its widest text, so they line up.
        float markX = 0;
        /// The reading's language in its own script, at the row's end.
        Com<IDWriteTextLayout> languageLayout;
        float languageWidth = 0;
        D2D1_RECT_F frame = {}; // in the page's coordinates (DIPs)
    };

    /// A value that moves from `from` to `to` over `duration` seconds from `start`, on the strip's
    /// curve (fast out, gentle in) or evenly.
    struct Motion {
        float from = 0, to = 0;
        double start = 0, duration = 0;
        bool ease = true;
        float At(double now) const;
        bool Moving(double now) const { return now < start + duration; }
        void Set(float value) { from = to = value; start = duration = 0; }
        /// From where it is now to `value`, starting `delay` seconds from now.
        void Go(float value, double now, double seconds, double delay = 0, bool eased = true);
    };

    HWND window_ = nullptr;
    UINT dpi_ = 96;
    POINT origin_ = {};  // the window's, screen pixels
    SIZE size_ = {};     // the window's, pixels
    Mode mode_ = Mode::none;
    std::vector<Cell> cells_;
    std::vector<std::wstring> texts_;
    std::wstring reading_;
    std::vector<Mark> marks_;
    int selected_ = 0;
    int page_ = 0;
    int pageStart_ = 0;
    bool above_ = false;
    /// The word the strip was put under: a correction folds back under it, whatever the key
    /// that made the correction started since.
    RECT word_ = {};
    std::wstring footer_;
    Com<IDWriteTextLayout> footerLayout_;
    /// The page, at the footer's other end.
    Com<IDWriteTextLayout> pageLayout_;
    std::function<void(int)> pick_, choose_;
    /// The strip's frame in the window (DIPs) and, for a card, its rows' inside.
    D2D1_RECT_F strip_ = {};
    D2D1_RECT_F inside_ = {};
    bool shown_ = false;
    bool hiding_ = false;

    // Motion: the thumb, the strip coming in, a page turned, the window fading.
    Motion thumbX_, thumbY_, thumbWidth_;
    Motion appear_, slide_, pageAlpha_, pageSlide_, alpha_;

    // Saying what a correction did.
    bool settling_ = false;
    std::string learning_;
    double settleStart_ = 0;
    int settleCell_ = 0;
    Motion trackLeft_, trackRight_, trackTop_, trackBottom_, trackRadius_, trackAlpha_, othersAlpha_, travel_, gray_, outcomeAlpha_;
    /// How long after the correction the mark moves.
    double settleSay_ = 0.24;
    Com<IDWriteTextLayout> outcome_;
    float markX_ = 0, outcomeX_ = 0;

    // The bitmap each frame is drawn into, then handed to the layered window.
    HDC dc_ = nullptr;
    HBITMAP bitmap_ = nullptr;
    HGDIOBJ oldBitmap_ = nullptr;
    SIZE bitmapSize_ = {};

    /// The card's width for the candidates it was last measured for.
    std::vector<std::wstring> measuredTexts_;
    std::wstring measuredFooter_;
    float measuredWidth_ = 0;

    /// `row`: a card's row, larger than a capsule on its own.
    Cell MakeCell(const std::wstring &text, int number, Mark mark, bool japanese, bool row = true) const;
    /// A row's height, the line its text sits on and that text's cap height in the current mode.
    float RowHeight() const;
    float Baseline() const;
    float CapHeight() const;
    float CardWidth(const std::vector<std::wstring> &texts, const std::wstring &footer, bool japanese);
    void Build(std::vector<Cell> cells, Mode mode, float cardWidth, int rows, int selected, const RECT &word, int turn);
    void Select(int index);
    bool Up() const { return shown_ && !hiding_; }
    void Start();
    void Frame();
    void Render(double now);
    void DrawCell(ID2D1RenderTarget *target, ID2D1SolidColorBrush *brush, const Cell &cell, bool on, float alpha,
                  bool settled, double now);
    void Click(int x, int y);
    void Clickable(bool clickable);
    static LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
};

}  // namespace araso
