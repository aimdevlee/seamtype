#include "Settings.h"
#include "SettingsInternal.h"
#include "resource.h"

#include <imm.h>
#include <windowsx.h>

#include <algorithm>

namespace araso {
namespace settings {

State g;

const SwitchKeyInfo kSwitchKeys[5] = {
    {"rightOption", "Right Alt tap", "Tap the right Alt (한/영 on Korean keyboards) on its own. Apps don't react to it."},
    {"optionSpace", "Alt+Space", "Alt and Space together. It no longer opens the window menu."},
    {"rightShift", "Right Shift tap", "Tap the right Shift on its own. Apps ignore it, so nothing else happens."},
    {"escape", "Esc", "Quick, but some apps also see the Esc and may close a dialog or clear the input."},
    {"shiftEscape", "Shift+Esc", "With nothing to change, it does nothing."},
};

namespace {

struct PaneInfo {
    const char *id;
    const char *title;
    const char *note;
    void (*build)();
};

const PaneInfo kPanes[] = {
    {"general", "Languages", "Which language each word is decided as.", BuildLanguages},
    {"keys", "Keys", "The keys that change a word's language, and a few more.", BuildKeys},
    {"apps", "Apps", "What every app does, and the apps that differ.", BuildApps},
    {"learning", "Dictionary", "Keys that always come out one way, also with a particle after them.", BuildDictionary},
    {"typing", "Try Typing", "Type here to see how each word is decided.", BuildTyping},
    {"about", "About", "Version, updates and files.", BuildAbout},
};
constexpr int kPaneCount = sizeof kPanes / sizeof kPanes[0];

int PaneIndex(const std::string &id) {
    for (int k = 0; k < kPaneCount; k++) if (id == kPanes[k].id) return k;
    return 0;
}

void MakeFonts() {
    for (HFONT *font : {&g.font, &g.bold, &g.fine, &g.title}) {
        if (*font) DeleteObject(*font);
    }
    NONCLIENTMETRICSW metrics = {sizeof metrics};
    SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof metrics, &metrics, 0, g.dpi);
    LOGFONTW base = metrics.lfMessageFont;
    auto make = [&](int pointsTimesTen, int weight) {
        LOGFONTW font = base;
        font.lfHeight = -MulDiv(pointsTimesTen, static_cast<int>(g.dpi), 720);
        font.lfWeight = weight;
        return CreateFontIndirectW(&font);
    };
    g.font = make(95, FW_NORMAL);
    g.fine = make(85, FW_NORMAL);
    g.bold = make(95, FW_SEMIBOLD);
    g.title = make(150, FW_SEMIBOLD);
}

/// Lays the pane out afresh: every control goes, and the pane builds its own again.
void BuildPane() {
    SendMessageW(g.content, WM_SETREDRAW, FALSE, 0);
    HWND child = GetWindow(g.content, GW_CHILD);
    while (child) {
        HWND next = GetWindow(child, GW_HWNDNEXT);
        DestroyWindow(child);
        child = next;
    }
    g.commands.clear();
    g.notifies.clear();
    g.notes.clear();
    g.wordList = nullptr;
    g.traceList = nullptr;
    g.nextId = 1000;
    RECT client;
    GetClientRect(g.content, &client);
    g.width = client.right;
    g.y = Pad();
    const PaneInfo &pane = kPanes[g.pane];
    Title(L(pane.title), L(pane.note));
    pane.build();
    // Tall panes make the window taller (up to the screen).
    RECT frame;
    GetWindowRect(g.frame, &frame);
    int needed = g.y + Pad() - client.bottom;
    if (needed > 0) {
        MONITORINFO monitor = {sizeof monitor};
        GetMonitorInfoW(MonitorFromWindow(g.frame, MONITOR_DEFAULTTONEAREST), &monitor);
        int height = std::min(static_cast<int>(frame.bottom - frame.top) + needed,
                              static_cast<int>(monitor.rcWork.bottom - frame.top));
        SetWindowPos(g.frame, nullptr, 0, 0, frame.right - frame.left, height, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
    SendMessageW(g.content, WM_SETREDRAW, TRUE, 0);
    RedrawWindow(g.content, nullptr, nullptr, RDW_ERASE | RDW_FRAME | RDW_INVALIDATE | RDW_ALLCHILDREN);
}

void Layout() {
    RECT client;
    GetClientRect(g.frame, &client);
    int side = S(180);
    MoveWindow(g.sidebar, 0, 0, side, client.bottom, TRUE);
    MoveWindow(g.content, side, 0, client.right - side, client.bottom, TRUE);
}

LRESULT CALLBACK ContentProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_COMMAND: {
        auto found = g.commands.find(LOWORD(wParam));
        if (found != g.commands.end()) found->second(reinterpret_cast<HWND>(lParam), HIWORD(wParam));
        return 0;
    }
    case WM_NOTIFY: {
        auto *header = reinterpret_cast<NMHDR *>(lParam);
        auto found = g.notifies.find(static_cast<int>(header->idFrom));
        if (found != g.notifies.end()) found->second(header);
        return 0;
    }
    case WM_CTLCOLORSTATIC: {
        HDC dc = reinterpret_cast<HDC>(wParam);
        SetBkMode(dc, TRANSPARENT);
        if (g.notes.count(reinterpret_cast<HWND>(lParam))) SetTextColor(dc, GetSysColor(COLOR_GRAYTEXT));
        return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
    }
    case WM_CTLCOLORBTN:
        return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

LRESULT CALLBACK FrameProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_SIZE:
        if (g.sidebar) Layout();
        return 0;
    case WM_COMMAND:
        if (reinterpret_cast<HWND>(lParam) == g.sidebar && HIWORD(wParam) == LBN_SELCHANGE) {
            ShowPane(ListBox_GetCurSel(g.sidebar));
        }
        return 0;
    case WM_CTLCOLORLISTBOX:
        return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_BTNFACE));
    case kRebuild:
        BuildPane();
        return 0;
    case kReleaseChecked:
        ReleaseChecked(reinterpret_cast<std::string *>(lParam));
        return 0;
    case kDownloaded:
        Downloaded(reinterpret_cast<std::wstring *>(lParam));
        return 0;
    case WM_COPYDATA: {
        auto *copy = reinterpret_cast<COPYDATASTRUCT *>(lParam);
        std::string data(static_cast<const char *>(copy->lpData), copy->cbData);
        if (copy->dwData == kCopyFilesChanged) {
            // The input menu changed the files, or an update check came back.
            LoadModel();
            if (g.pane != PaneIndex("typing")) Rebuild();
        } else if (copy->dwData == kCopyShowTab) {
            ShowPane(PaneIndex(data));
            if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
            SetForegroundWindow(window);
        }
        return TRUE;
    }
    case WM_DPICHANGED: {
        g.dpi = HIWORD(wParam);
        MakeFonts();
        SendMessageW(g.sidebar, WM_SETFONT, reinterpret_cast<WPARAM>(g.font), TRUE);
        auto *suggested = reinterpret_cast<RECT *>(lParam);
        SetWindowPos(window, nullptr, suggested->left, suggested->top, suggested->right - suggested->left,
                     suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
        Rebuild();
        return 0;
    }
    case WM_GETMINMAXINFO: {
        auto *info = reinterpret_cast<MINMAXINFO *>(lParam);
        info->ptMinTrackSize.x = S(760);
        info->ptMinTrackSize.y = S(560);
        return 0;
    }
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    static const UINT traceMessage = RegisterWindowMessageW(kTraceMessage);
    if (message == traceMessage && lParam) {
        char *text = reinterpret_cast<char *>(lParam);
        AddTrace(Json::parse(text));
        HeapFree(GetProcessHeap(), 0, text);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

}  // namespace

// MARK: - Model

int S(int value) { return MulDiv(value, static_cast<int>(g.dpi), 96); }

Json Request(Json request) { return Bridge::Shared().Request(request); }

void LoadModel() {
    Json request = Json::object();
    request.set("op", "settings");
    Json model = Request(request)["settings"];
    if (model.isObject()) g.model = model;
}

void Rebuild() { PostMessageW(g.frame, kRebuild, 0, 0); }

void ShowPane(int pane) {
    g.pane = std::max(0, std::min(pane, kPaneCount - 1));
    ListBox_SetCurSel(g.sidebar, g.pane);
    BuildPane();
}

/// The host reads the files again (and drops its kanji learning when `kanjiReset`).
static void TellHost(bool kanjiReset) {
    HWND host = FindWindowW(kHostWindowClass, nullptr);
    if (!host) return;
    std::string data = kanjiReset ? "kanjiReset" : "";
    COPYDATASTRUCT copy = {kCopyReload, static_cast<DWORD>(data.size()), data.data()};
    SendMessageTimeoutW(host, WM_COPYDATA, reinterpret_cast<WPARAM>(g.frame), reinterpret_cast<LPARAM>(&copy),
                        SMTO_ABORTIFHUNG, 2000, nullptr);
}

void Apply(Json change, bool kanjiReset) {
    Json request = Json::object();
    request.set("op", "change");
    request.set("change", change);
    Json response = Request(request);
    if (response["settings"].isObject()) g.model = response["settings"];
    TellHost(kanjiReset);
    Rebuild();
}

void ChangeSettings(const std::function<void(Json &)> &edit) {
    Json settings = g.model["settings"];
    edit(settings);
    Json change = Json::object();
    change.set("settings", settings);
    Apply(change);
}

void ChangeDefault(const std::function<void(Json &)> &edit) {
    Json policy = g.model["defaultPolicy"];
    edit(policy);
    Json change = Json::object();
    change.set("defaultPolicy", policy);
    Apply(change);
}

Json AppEntry(const std::string &app) {
    for (const Json &item : g.model["apps"].items()) {
        if (item["app"].asString() == app && item["entry"].isObject()) return item["entry"];
    }
    return Json::object();
}

void ChangeApp(const std::string &app, const std::function<void(Json &)> &edit) {
    Json entry = AppEntry(app);
    edit(entry);
    Json change = Json::object();
    change.set("app", app);
    change.set("entry", entry);
    Apply(change);
}

bool HasKey(const Json &keys, const std::string &id) {
    for (const Json &key : keys.items()) if (key.asString() == id) return true;
    return false;
}

Json WithKey(const Json &keys, const std::string &id, bool on) {
    Json out = Json::array();
    for (const auto &info : kSwitchKeys) {
        bool has = id == info.id ? on : HasKey(keys, info.id);
        if (has) out.push(info.id);
    }
    return out;
}

std::wstring KeyNames(const Json &keys) {
    std::wstring out;
    for (const auto &info : kSwitchKeys) {
        if (!HasKey(keys, info.id)) continue;
        if (!out.empty()) out += L", ";
        out += L(info.name);
    }
    return out;
}

// MARK: - Layout

int Pad() { return S(24); }
int ContentWidth() { return g.width - 2 * Pad(); }

HWND Make(const wchar_t *cls, const std::wstring &text, DWORD style, int x, int y, int w, int h, HFONT font,
          std::function<void(HWND, int)> command) {
    int id = g.nextId++;
    HWND control = CreateWindowExW(0, cls, text.c_str(), WS_CHILD | WS_VISIBLE | style, x, y, w, h, g.content,
                                   reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font ? font : g.font), TRUE);
    if (command) g.commands[id] = std::move(command);
    return control;
}

static int TextHeight(const std::wstring &text, HFONT font, int width) {
    HDC dc = GetDC(g.content);
    HGDIOBJ old = SelectObject(dc, font);
    RECT rect = {0, 0, width, 0};
    DrawTextW(dc, text.c_str(), -1, &rect, DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
    SelectObject(dc, old);
    ReleaseDC(g.content, dc);
    return rect.bottom;
}

void Title(const std::wstring &text, const std::wstring &note) {
    Make(L"STATIC", text, SS_NOPREFIX, Pad(), g.y, ContentWidth(), S(30), g.title);
    g.y += S(36);
    int h = TextHeight(note, g.font, ContentWidth());
    g.notes.insert(Make(L"STATIC", note, SS_NOPREFIX, Pad(), g.y, ContentWidth(), h, g.font));
    g.y += h + S(16);
}

void Heading(const std::wstring &text) {
    g.y += S(6);
    Make(L"STATIC", text, SS_NOPREFIX, Pad(), g.y, ContentWidth(), S(20), g.bold);
    g.y += S(26);
}

void Note(const std::wstring &text, int indent) {
    int width = ContentWidth() - indent;
    int h = TextHeight(text, g.fine, width);
    g.notes.insert(Make(L"STATIC", text, SS_NOPREFIX, Pad() + indent, g.y, width, h, g.fine));
    g.y += h + S(8);
}

HWND Check(const std::wstring &text, bool on, bool enabled, std::function<void(bool)> changed, int indent) {
    HWND box = Make(L"BUTTON", text, BS_AUTOCHECKBOX | WS_TABSTOP, Pad() + indent, g.y, ContentWidth() - indent, S(22),
                    g.font, [changed](HWND control, int code) {
                        if (code == BN_CLICKED) changed(Button_GetCheck(control) == BST_CHECKED);
                    });
    Button_SetCheck(box, on ? BST_CHECKED : BST_UNCHECKED);
    EnableWindow(box, enabled);
    g.y += S(24);
    return box;
}

HWND Combo(const std::wstring &label, const std::vector<std::wstring> &items, int selected, bool enabled,
           std::function<void(int)> changed, int indent) {
    int labelWidth = S(160);
    HWND name = Make(L"STATIC", label, SS_NOPREFIX | SS_CENTERIMAGE, Pad() + indent, g.y, labelWidth, S(26), g.font);
    EnableWindow(name, enabled);
    HWND box = Make(WC_COMBOBOXW, L"", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, Pad() + indent + labelWidth, g.y,
                    std::min(S(300), ContentWidth() - indent - labelWidth), S(300), g.font,
                    [changed](HWND control, int code) {
                        if (code == CBN_SELCHANGE) changed(ComboBox_GetCurSel(control));
                    });
    for (const auto &item : items) ComboBox_AddString(box, item.c_str());
    ComboBox_SetCurSel(box, selected);
    EnableWindow(box, enabled);
    g.y += S(32);
    return box;
}

HWND Push(const std::wstring &text, int x, int width, std::function<void()> clicked, bool enabled) {
    HWND button = Make(L"BUTTON", text, BS_PUSHBUTTON | WS_TABSTOP, x, g.y, width, S(28), g.font,
                       [clicked](HWND, int code) { if (code == BN_CLICKED) clicked(); });
    EnableWindow(button, enabled);
    return button;
}

HWND List(const std::vector<std::pair<std::wstring, int>> &columns, int height) {
    HWND list = Make(WC_LISTVIEWW, L"", LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_TABSTOP | WS_BORDER, Pad(),
                     g.y, ContentWidth(), height, g.font);
    ListView_SetExtendedListViewStyle(list, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
    int index = 0;
    for (const auto &column : columns) {
        LVCOLUMNW info = {};
        info.mask = LVCF_TEXT | LVCF_WIDTH;
        info.pszText = const_cast<wchar_t *>(column.first.c_str());
        info.cx = S(column.second);
        ListView_InsertColumn(list, index++, &info);
    }
    g.y += height + S(8);
    return list;
}

void Row(HWND list, int row, const std::vector<std::wstring> &cells) {
    LVITEMW item = {};
    item.mask = LVIF_TEXT;
    item.iItem = row;
    item.pszText = const_cast<wchar_t *>(cells[0].c_str());
    ListView_InsertItem(list, &item);
    for (size_t k = 1; k < cells.size(); k++) {
        ListView_SetItemText(list, row, static_cast<int>(k), const_cast<wchar_t *>(cells[k].c_str()));
    }
}

int Selected(HWND list) { return ListView_GetNextItem(list, -1, LVNI_SELECTED); }

bool Confirm(const std::wstring &question, const std::wstring &detail) {
    std::wstring text = question + L"\n\n" + detail;
    return MessageBoxW(g.frame, text.c_str(), L"Araso", MB_OKCANCEL | MB_ICONQUESTION | MB_DEFBUTTON2) == IDOK;
}

void WithoutInputMethod(HWND control) { ImmAssociateContextEx(control, nullptr, 0); }

// MARK: - Dialog

Dialog::Dialog(const std::wstring &title, int width, int height) {
    static bool registered = false;
    if (!registered) {
        WNDCLASSEXW cls = {sizeof cls};
        cls.lpfnWndProc = Proc;
        cls.hInstance = GetModuleHandleW(nullptr);
        cls.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        cls.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
        cls.lpszClassName = L"ArasoDialog";
        RegisterClassExW(&cls);
        registered = true;
    }
    RECT frame;
    GetWindowRect(g.frame, &frame);
    RECT size = {0, 0, S(width), S(height)};
    AdjustWindowRectExForDpi(&size, WS_CAPTION | WS_SYSMENU, FALSE, WS_EX_DLGMODALFRAME, g.dpi);
    int w = size.right - size.left, h = size.bottom - size.top;
    window_ = CreateWindowExW(WS_EX_DLGMODALFRAME, L"ArasoDialog", title.c_str(), WS_CAPTION | WS_SYSMENU | WS_POPUP,
                              frame.left + (frame.right - frame.left - w) / 2, frame.top + S(80), w, h, g.frame, nullptr,
                              GetModuleHandleW(nullptr), this);
}

HWND Dialog::Add(const wchar_t *cls, const std::wstring &text, DWORD style, int x, int y, int w, int h,
                 std::function<void(HWND, int)> command, HFONT font) {
    int id = next_++;
    HWND control = CreateWindowExW(0, cls, text.c_str(), WS_CHILD | WS_VISIBLE | style, S(x), S(y), S(w), S(h), window_,
                                   reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font ? font : g.font), TRUE);
    if (command) commands_[id] = std::move(command);
    return control;
}

void Dialog::TakeKeys(HWND control, std::function<bool(WPARAM, LPARAM)> handler) {
    keysControl_ = control;
    keys_ = std::move(handler);
}

bool Dialog::Run() {
    EnableWindow(g.frame, FALSE);
    ShowWindow(window_, SW_SHOW);
    if (keysControl_) SetFocus(keysControl_);
    MSG message;
    while (!done_ && GetMessageW(&message, nullptr, 0, 0) > 0) {
        bool key = message.message == WM_KEYDOWN || message.message == WM_SYSKEYDOWN;
        if (key && keys_ && message.hwnd == keysControl_ && keys_(message.wParam, message.lParam)) continue;
        if (!IsDialogMessageW(window_, &message)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    EnableWindow(g.frame, TRUE);
    SetForegroundWindow(g.frame);
    DestroyWindow(window_);
    return accepted_;
}

void Dialog::Close(bool accepted) {
    accepted_ = accepted;
    done_ = true;
}

LRESULT CALLBACK Dialog::Proc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_NCCREATE) {
        auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto *self = reinterpret_cast<Dialog *>(GetWindowLongPtrW(window, GWLP_USERDATA));
    switch (message) {
    case WM_COMMAND:
        if (self) {
            if (LOWORD(wParam) == IDCANCEL) {
                self->Close(false);
                return 0;
            }
            auto found = self->commands_.find(LOWORD(wParam));
            if (found != self->commands_.end()) found->second(reinterpret_cast<HWND>(lParam), HIWORD(wParam));
        }
        return 0;
    case WM_CLOSE:
        if (self) self->Close(false);
        return 0;
    case WM_CTLCOLORSTATIC:
        SetBkMode(reinterpret_cast<HDC>(wParam), TRANSPARENT);
        return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

}  // namespace settings

int RunSettings(const std::string &tab) {
    using namespace settings;
    // One settings window: an open one comes forward on the pane asked for.
    if (HWND open = FindWindowW(kSettingsWindowClass, nullptr)) {
        COPYDATASTRUCT copy = {kCopyShowTab, static_cast<DWORD>(tab.size()), const_cast<char *>(tab.data())};
        SendMessageTimeoutW(open, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy), SMTO_ABORTIFHUNG, 1000, nullptr);
        SetForegroundWindow(open);
        return 0;
    }
    std::wstring error;
    if (!Bridge::Shared().Start(error, false)) {
        MessageBoxW(nullptr, error.c_str(), L"Araso", MB_ICONERROR);
        return 1;
    }
    LoadModel();

    HINSTANCE instance = GetModuleHandleW(nullptr);
    WNDCLASSEXW frameClass = {sizeof frameClass};
    frameClass.lpfnWndProc = FrameProc;
    frameClass.hInstance = instance;
    frameClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    frameClass.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
    frameClass.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_HOST));
    frameClass.lpszClassName = kSettingsWindowClass;
    RegisterClassExW(&frameClass);
    WNDCLASSEXW contentClass = {sizeof contentClass};
    contentClass.lpfnWndProc = ContentProc;
    contentClass.hInstance = instance;
    contentClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    contentClass.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
    contentClass.lpszClassName = L"ArasoSettingsPane";
    RegisterClassExW(&contentClass);

    POINT cursor;
    GetCursorPos(&cursor);
    HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info = {sizeof info};
    GetMonitorInfoW(monitor, &info);
    // The window's own DPI is read again once it exists.
    g.dpi = GetDpiForSystem();
    int width = S(820), height = S(620);
    int x = info.rcWork.left + (info.rcWork.right - info.rcWork.left - width) / 2;
    int y = info.rcWork.top + (info.rcWork.bottom - info.rcWork.top - height) / 3;
    g.frame = CreateWindowExW(0, kSettingsWindowClass, L("Araso Settings").c_str(), WS_OVERLAPPEDWINDOW, x, y, width,
                              height, nullptr, nullptr, instance, nullptr);
    if (!g.frame) return 1;
    g.dpi = GetDpiForWindow(g.frame);
    MakeFonts();
    ChangeWindowMessageFilterEx(g.frame, WM_COPYDATA, MSGFLT_ALLOW, nullptr);
    g.sidebar = CreateWindowExW(0, WC_LISTBOXW, L"", WS_CHILD | WS_VISIBLE | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT, 0, 0, 0, 0,
                                g.frame, nullptr, instance, nullptr);
    SendMessageW(g.sidebar, WM_SETFONT, reinterpret_cast<WPARAM>(g.font), TRUE);
    SendMessageW(g.sidebar, LB_SETITEMHEIGHT, 0, S(34));
    for (const auto &pane : kPanes) ListBox_AddString(g.sidebar, (L"   " + L(pane.title)).c_str());
    g.content = CreateWindowExW(WS_EX_CONTROLPARENT, L"ArasoSettingsPane", L"", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
                                0, 0, 0, 0, g.frame, nullptr, instance, nullptr);
    Layout();
    ShowPane(PaneIndex(tab));
    ShowWindow(g.frame, SW_SHOW);
    SetForegroundWindow(g.frame);
    // As on macOS: the window checks for updates when it opens.
    if (g.model["settings"]["checkForUpdates"].asBool(true)) CheckForUpdates();

    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        if (!IsDialogMessageW(g.frame, &message)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    return 0;
}

}  // namespace araso
