import Foundation

/// RetroMac's widgets (clock, calculator, Notepad, CPU monitor) under QNX 6.2.1 (Lastenheft 3.0,
/// QNX-10). Like CDE's, the widget pages draw their Windows 98 furniture (`RetroFrameTheme.widgetKey`)
/// and this layer repaints it as Photon drew a window: the title bar across the full width, black
/// and #3F3F3F, a light line, a groove and the blue gradient; minimise and maximise together and
/// close apart on the right; #D9D9D9 faces; the 5 pt frame. The measurements are the ones of the
/// title bars over real windows (docs/reference). A widget has no window menu, so no menu box.
enum PhotonWidgetChrome {
    static let css = """
    body.theme-photon.theme-win98, body.theme-photon.theme-win98 .w98-menubar, body.theme-photon.theme-win98 .np-status,
    body.theme-photon.theme-win98 .w98-menubar span, body.theme-photon.theme-win98 .menu, body.theme-photon.theme-win98 .w98-mi {
      font-family:"Lucida Grande",Helvetica,sans-serif!important; }
    body.theme-photon.theme-win98 #win, body.theme-photon.theme-win98 .window {
      background:#D9D9D9!important; padding:0 5px 5px!important; border:none!important; border-radius:0!important;
      box-shadow:inset 1px 0 0 #000,inset -1px -1px 0 #000,inset 2px 0 0 #3F3F3F,inset -2px -2px 0 #3F3F3F,
                 inset 3px 0 0 #FFF,inset -3px -3px 0 #9D9D9D,inset 4px 0 0 #D9D9D9,inset -4px -4px 0 #D9D9D9!important; }
    body.theme-photon.theme-win98 .w98-title {
      position:relative; margin:0 -5px 0!important; height:21px!important; flex:0 0 21px!important; padding:0 4px 0 0!important; gap:0!important;
      justify-content:flex-end;
      background:linear-gradient(to bottom,#000 0 1px,#3F3F3F 1px 2px,#8EBDFF 2px 3px,#5C8BDF 3px 4px,#2A59AD 4px 5px,
                 #5C8BDF 5px 6px,#6695E9 6px,#4776CA 20px,#2A59AD 20px 21px)!important;
      box-shadow:inset 1px 0 0 #000,inset -1px 0 0 #000,inset 2px 0 0 #3F3F3F,inset -2px 0 0 #3F3F3F,inset 3px 0 0 #8EBDFF; }
    body.theme-photon.theme-win98 .w98-ico { display:none!important; }
    body.theme-photon.theme-win98 .w98-cap {
      position:absolute; left:0; right:0; top:5px; height:15px; display:flex!important; align-items:center; justify-content:center;
      margin:0!important; padding:0!important; color:#000065!important; text-shadow:none!important; pointer-events:none;
      font:400 12px "Lucida Grande",Helvetica,sans-serif!important; font-weight:400!important; }
    body.theme-photon.theme-win98 .w98-title .w98-btn {
      position:relative; z-index:1; align-self:flex-start; margin:4px 0 0!important; padding:0!important; height:15px!important;
      border:none!important; background:#D6D6D6!important; font-size:0!important; color:transparent!important;
      box-shadow:inset 1px 1px 0 #F6F6F6,inset -1px -1px 0 #3F3F3F!important; }
    body.theme-photon.theme-win98 .w98-title .w98-btn.is-press { box-shadow:inset 1px 1px 0 #3F3F3F,inset -1px -1px 0 #F6F6F6!important; }
    body.theme-photon.theme-win98 #w98min { width:17px!important; flex:0 0 17px!important; }
    body.theme-photon.theme-win98 #w98max { width:16px!important; flex:0 0 16px!important; }
    body.theme-photon.theme-win98 #w98close { width:20px!important; flex:0 0 20px!important; margin-left:8px!important; }
    body.theme-photon.theme-win98 .w98-title .w98-btn::before, body.theme-photon.theme-win98 .w98-title .w98-btn::after {
      content:none!important; transform:none!important; background:none!important; border:none!important; box-shadow:none!important; }
    body.theme-photon.theme-win98 #w98max::before {
      content:""!important; position:absolute!important; left:3px!important; top:3px!important; right:auto!important; bottom:auto!important;
      width:8px!important; height:7px!important; border:1px solid #3E3C3E!important; }
    body.theme-photon.theme-win98 #w98close::before {
      content:""!important; position:absolute!important; left:4px!important; top:2px!important; right:auto!important; bottom:auto!important;
      width:10px!important; height:9px!important; border:1px solid #3E3C3E!important; }
    body.theme-photon.theme-win98 #w98close::after {
      content:""!important; position:absolute!important; left:8px!important; top:6px!important; width:4px!important; height:3px!important;
      background:#3E3C3E!important; }
    body.theme-photon.theme-win98 #w98min::before {
      content:""!important; position:absolute!important; left:5px!important; top:5px!important; width:0!important; height:0!important;
      border-left:3px solid transparent!important; border-right:3px solid transparent!important; border-top:3px solid #3E3C3E!important; }
    body.theme-photon.theme-win98 #w98min::after {
      content:""!important; position:absolute!important; left:4px!important; bottom:3px!important; width:9px!important; height:1px!important;
      background:#3E3C3E!important; }
    /* The CPU monitor draws at 0.6 and counter-scales its chrome, as every theme there does. */
    body.theme-photon.theme-win98 .window .w98-title { zoom:1.6667; margin:0 -3px!important; }
    body.theme-photon.theme-win98 .body, body.theme-photon.theme-win98 .np-toolbar, body.theme-photon.theme-win98 .memind,
    body.theme-photon.theme-win98 .w98-menubar, body.theme-photon.theme-win98 .np-status, body.theme-photon.theme-win98 .menu {
      background:#D9D9D9!important; }
    body.theme-photon.theme-win98 .w98-menubar, body.theme-photon.theme-win98 .np-toolbar, body.theme-photon.theme-win98 .np-status {
      border:none!important; box-shadow:inset 1px 1px 0 #FFF,inset -1px -1px 0 #A7A7A7!important; }
    body.theme-photon.theme-win98 .w98-menubar span { font-size:13px!important; color:#000!important; }
    body.theme-photon.theme-win98 .k, body.theme-photon.theme-win98 button {
      background:#D9D9D9!important; border:1px solid #4B4B4B!important; border-radius:0!important; color:#000!important;
      box-shadow:inset 1px 1px 0 #FFF,inset -1px -1px 0 #A7A7A7!important; }
    body.theme-photon.theme-win98 .k:active, body.theme-photon.theme-win98 button:active {
      background:#C0C0C0!important; box-shadow:inset 1px 1px 0 #8E8E8E!important; }
    body.theme-photon.theme-win98 #pad, body.theme-photon.theme-win98 textarea, body.theme-photon.theme-win98 input,
    body.theme-photon.theme-win98 .display, body.theme-photon.theme-win98 #display {
      background:#FFF!important; color:#000!important; border:1px solid #4B4B4B!important; box-shadow:inset 1px 1px 0 #8E8E8E!important; }
    """

    /// Marks the page as Photon and lays the repaint over its Windows 98 chrome.
    static let js = "(function(){var e=document.getElementById('w98scheme'); if(e) e.remove(); document.body.classList.add('theme-photon');"
        + " var st=document.createElement('style'); st.id='w98scheme'; st.textContent=`\(css)`; document.head.appendChild(st);})();"
}
