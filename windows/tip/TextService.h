// Araso's text service: what InputController is on macOS. Every key goes to the host with a
// snapshot of the field (the selection, the composition, the text before them); the edits the
// session made come back and are made here, inside an edit session, in order.
#pragma once

#include "Tsf.h"
#include "HostConnection.h"

#include <functional>
#include <vector>

namespace araso {

class LangBarButton;

class TextService final : public ITfTextInputProcessorEx,
                          public ITfThreadMgrEventSink,
                          public ITfKeyEventSink,
                          public ITfCompositionSink,
                          public ITfDisplayAttributeProvider {
public:
    TextService();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor(Ex)
    STDMETHODIMP Activate(ITfThreadMgr *threadMgr, TfClientId clientId) override;
    STDMETHODIMP ActivateEx(ITfThreadMgr *threadMgr, TfClientId clientId, DWORD flags) override;
    STDMETHODIMP Deactivate() override;

    // ITfThreadMgrEventSink
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr *) override { return S_OK; }
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr *) override { return S_OK; }
    STDMETHODIMP OnSetFocus(ITfDocumentMgr *focus, ITfDocumentMgr *previous) override;
    STDMETHODIMP OnPushContext(ITfContext *) override { return S_OK; }
    STDMETHODIMP OnPopContext(ITfContext *) override { return S_OK; }

    // ITfKeyEventSink
    STDMETHODIMP OnSetFocus(BOOL foreground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnKeyUp(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext *, REFGUID, BOOL *eaten) override { *eaten = FALSE; return S_OK; }

    // ITfCompositionSink
    STDMETHODIMP OnCompositionTerminated(TfEditCookie cookie, ITfComposition *composition) override;

    // ITfDisplayAttributeProvider
    STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo **enumerator) override;
    STDMETHODIMP GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo **info) override;

    // The language bar button's menu.
    Json Menu();
    void MenuSelect(const std::string &item);

    /// The host has edits waiting for this client.
    void FetchPending();

private:
    ~TextService();

    LONG references_ = 1;
    ITfThreadMgr *threadMgr_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    DWORD threadMgrSinkCookie_ = TF_INVALID_COOKIE;
    bool keySinkAdvised_ = false;
    ITfComposition *composition_ = nullptr;
    /// The context the composition is in (focus can move before it ends).
    ITfContext *compositionContext_ = nullptr;
    LangBarButton *button_ = nullptr;
    HWND window_ = nullptr;
    HostConnection host_;
    TfGuidAtom attrInput_ = TF_INVALID_GUIDATOM;
    TfGuidAtom attrConverted_ = TF_INVALID_GUIDATOM;
    TfGuidAtom attrTarget_ = TF_INVALID_GUIDATOM;
    std::wstring app_;
    /// A key event: the same press seen again (TSF may test a key more than once) gets the first answer.
    struct Seen {
        bool valid = false;
        WPARAM vk = 0;
        LPARAM lParam = 0;
        DWORD at = 0;
        bool taken = false;
        bool Is(WPARAM v, LPARAM l) const { return valid && vk == v && lParam == l && GetTickCount() - at < 1000; }
    };
    /// The host's answer for the key being pressed (`HostTakes`).
    Seen asked_;
    /// The modifier going down that the host was told of (`SeeModifier`).
    Seen seen_;
    /// A key sent again for the app (`Replay`): it passes when it comes back.
    Seen replayed_;
    /// Keys whose down this text service kept: their up is kept too, as an input method's is
    /// (an app shown a key going up for a key it never saw go down may end the composition).
    bool keptDown_[256] = {};

    /// Classic apps (IMM32, through Windows' compatibility layer, CUAS) end a Korean input method's
    /// composition as soon as it starts. There the word being typed is kept here, shown to the
    /// session as if composed at the caret and drawn there by the host, and goes in whole.
    std::wstring floating_;
    ITfContext *floatingContext_ = nullptr;
    bool previewShown_ = false;
    /// An app was seen ending a composition at once, where its context didn't say it would.
    bool appEndsCompositions_ = false;
    DWORD compositionStartedAt_ = 0;
    bool Floats(ITfContext *context);
    void ApplyFloating(TfEditCookie cookie, ITfContext *context, const Json &op);
    void InsertAtCaret(TfEditCookie cookie, ITfContext *context, const std::wstring &text);
    void ClearFloating();

    bool Takes(WPARAM wParam, LPARAM lParam, bool down) const;
    bool HostTakes(WPARAM wParam, LPARAM lParam, bool up);
    void SeeModifier(ITfContext *context, WPARAM wParam, LPARAM lParam);
    void HandleKey(ITfContext *context, WPARAM wParam, LPARAM lParam, const char *op, BOOL *eaten);
    void Replay(WPARAM wParam, LPARAM lParam);
    Json KeyJson(WPARAM wParam, LPARAM lParam) const;
    /// Runs `body` in an edit session on `context`: synchronously when `sync`, else when TSF can.
    HRESULT Edit(ITfContext *context, bool sync, std::function<HRESULT(TfEditCookie)> body);

    /// The field around the caret (`TextContext`), and whether it is a password field.
    Json Snapshot(TfEditCookie cookie, ITfContext *context, bool &masked);
    Json Rects(TfEditCookie cookie, ITfContext *context);
    void ApplyOps(TfEditCookie cookie, ITfContext *context, const Json &ops, bool converting);
    void ApplyAttributes(TfEditCookie cookie, ITfContext *context, ITfRange *range, bool converting, const Json &clause);
    void ClearAttributes(TfEditCookie cookie, ITfContext *context, ITfRange *range);
    void EndComposition(TfEditCookie cookie);
    void MoveCaretToEnd(TfEditCookie cookie, ITfContext *context, ITfRange *range);
    ITfRange *RangeAt(TfEditCookie cookie, ITfContext *context, LONG start, LONG length);
    /// Sends a request whose answer carries edits, makes them and tells the host where things are.
    bool Exchange(TfEditCookie cookie, ITfContext *context, Json request, bool &handled, bool *replay = nullptr);
    ITfContext *FocusedContext();
    void CommitIn(ITfContext *context, const char *op);

    bool CreateMessageWindow();
    void DestroyMessageWindow();
    void RegisterAttributes();
    static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
};

/// Edits a context in TSF's edit session, by a function.
class EditSession final : public ITfEditSession {
public:
    explicit EditSession(std::function<HRESULT(TfEditCookie)> body) : body_(std::move(body)) {}

    STDMETHODIMP QueryInterface(REFIID riid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&references_); }
    STDMETHODIMP_(ULONG) Release() override {
        LONG count = InterlockedDecrement(&references_);
        if (!count) delete this;
        return count;
    }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override { return body_(cookie); }

private:
    LONG references_ = 1;
    std::function<HRESULT(TfEditCookie)> body_;
};

}  // namespace araso
