import Foundation

/// RetroMac's own widgets (clock, calculator, Notepad, CPU monitor) under the Solaris 8 theme
/// (Lastenheft 3.0, TH-01). The widget pages have no CDE chrome of their own: they draw their
/// Windows 98 furniture (`RetroFrameTheme.widgetKey`), title bar, menu bar and status line, and
/// this layer repaints it as dtwm drew a window. The 5 pt mauve frame, the 19 pt title bar with
/// the window-menu box on the left, the grey #ADB5C6 faces with 1 pt Motif bevels, and text
/// fields in #FFF7EF, as measured for the theme (docs/reference). The window-menu box closes the
/// widget; the full window menu is for real windows and the Application Manager.
enum CDEWidgetChrome {
    static let css = """
    body.theme-cde.theme-win98, body.theme-cde.theme-win98 .w98-menubar, body.theme-cde.theme-win98 .np-status,
    body.theme-cde.theme-win98 .w98-menubar span, body.theme-cde.theme-win98 .menu, body.theme-cde.theme-win98 .w98-mi {
      font-family:"Lucida Grande",Helvetica,sans-serif!important; }
    body.theme-cde.theme-win98 #win, body.theme-cde.theme-win98 .window {
      background:#ADB5C6!important; padding:5px!important; border:none!important; border-radius:0!important;
      box-shadow:inset 2px 2px 0 #DEADC6,inset -2px -2px 0 #522139,inset 4px 4px 0 #B54A7B,inset -4px -4px 0 #B54A7B,
                 inset 5px 5px 0 #522139,inset -5px -5px 0 #DEADC6!important; }
    body.theme-cde.theme-win98 .w98-title {
      margin:0!important; height:19px!important; flex:0 0 19px!important; padding:0!important; gap:0!important;
      background:#B54A7B!important; }
    body.theme-cde.theme-win98 .w98-ico { display:none!important; }
    /* The CPU monitor draws at 0.6 and counter-scales its chrome, as every theme there does. */
    body.theme-cde.theme-win98 .window .w98-title { zoom:1.6667; }
    body.theme-cde.theme-win98 .window { padding:8.33px!important;
      box-shadow:inset 3.33px 3.33px 0 #DEADC6,inset -3.33px -3.33px 0 #522139,inset 6.67px 6.67px 0 #B54A7B,inset -6.67px -6.67px 0 #B54A7B,
                 inset 8.33px 8.33px 0 #522139,inset -8.33px -8.33px 0 #DEADC6!important; }
    body.theme-cde.theme-win98 .w98-cap {
      flex:1 1 auto!important; align-self:stretch; display:flex!important; align-items:center; justify-content:center;
      margin:0!important; padding:0!important; color:#fff!important; text-shadow:none!important;
      font:400 13px "Lucida Grande",Helvetica,sans-serif!important; font-weight:400!important; box-shadow:inset 1px 1px 0 #DEADC6,inset -1px -1px 0 #522139; }
    body.theme-cde.theme-win98 .w98-title .w98-btn {
      position:relative; width:19px!important; height:19px!important; flex:0 0 19px!important; margin:0!important; padding:0!important;
      border:none!important; background:#B54A7B!important; font-size:0!important; color:transparent!important;
      box-shadow:inset 1px 1px 0 #DEADC6,inset -1px -1px 0 #522139!important; }
    body.theme-cde.theme-win98 .w98-title .w98-btn.is-press { box-shadow:inset 1px 1px 0 #522139,inset -1px -1px 0 #DEADC6!important; }
    body.theme-cde.theme-win98 #w98close { order:-1; }
    body.theme-cde.theme-win98 .w98-title .w98-btn::after { content:none!important; }
    body.theme-cde.theme-win98 .w98-title .w98-btn::before {
      content:""!important; position:absolute!important; transform:none!important; background:none!important; border:none!important;
      right:auto!important; bottom:auto!important; box-shadow:inset 1px 1px 0 #DEADC6,inset -1px -1px 0 #522139!important; }
    body.theme-cde.theme-win98 #w98close::before { left:5px!important; top:8px!important; width:10px!important; height:3px!important; }
    body.theme-cde.theme-win98 #w98min::before { left:7px!important; top:7px!important; width:5px!important; height:5px!important; }
    body.theme-cde.theme-win98 #w98max::before { left:3px!important; top:3px!important; width:13px!important; height:13px!important; }
    body.theme-cde.theme-win98 .body, body.theme-cde.theme-win98 .np-toolbar, body.theme-cde.theme-win98 .memind,
    body.theme-cde.theme-win98 .w98-menubar, body.theme-cde.theme-win98 .np-status, body.theme-cde.theme-win98 .menu {
      background:#ADB5C6!important; }
    body.theme-cde.theme-win98 .w98-menubar, body.theme-cde.theme-win98 .np-toolbar, body.theme-cde.theme-win98 .np-status {
      border:none!important; box-shadow:inset 1px 1px 0 #DEDEE7,inset -1px -1px 0 #5A636B!important; }
    body.theme-cde.theme-win98 .w98-menubar span { font-size:14px!important; color:#000!important; }
    body.theme-cde.theme-win98 .k, body.theme-cde.theme-win98 button {
      background:#ADB5C6!important; border:none!important; border-radius:0!important; color:#000!important;
      box-shadow:inset 1px 1px 0 #DEDEE7,inset -1px -1px 0 #5A636B!important; }
    body.theme-cde.theme-win98 .k:active, body.theme-cde.theme-win98 button:active {
      background:#9494A5!important; box-shadow:inset 1px 1px 0 #5A636B,inset -1px -1px 0 #DEDEE7!important; }
    body.theme-cde.theme-win98 #pad, body.theme-cde.theme-win98 textarea, body.theme-cde.theme-win98 input,
    body.theme-cde.theme-win98 .display, body.theme-cde.theme-win98 #display {
      background:#FFF7EF!important; color:#000!important; border:none!important;
      box-shadow:inset 1px 1px 0 #5A636B,inset -1px -1px 0 #DEDEE7!important; }
    """

    /// Marks the page as CDE and lays the repaint over its Windows 98 chrome. Wrapped in a function
    /// like the Win98 scheme injection, so nothing collides with the page's own globals.
    static let js = "(function(){var e=document.getElementById('w98scheme'); if(e) e.remove(); document.body.classList.add('theme-cde');"
        + " var st=document.createElement('style'); st.id='w98scheme'; st.textContent=`\(css)`; document.head.appendChild(st);})();"
}
