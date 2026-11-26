import Foundation

/// RetroMac's widgets (clock, calculator, Notepad, CPU monitor) under KDE 1.0. Qt 1's Windows
/// style is close to the Windows 98 furniture the pages draw (`RetroFrameTheme.widgetKey`), so
/// this layer changes only what kwm drew differently: the title shaded horizontally from the
/// active colour into the blend (kwm main.C: activeBackground darkBlue, activeBlend black,
/// TitlebarLook shadedHorizontal), Helvetica for the text, and the 4 pt frame (BORDER 4).
enum KDEWidgetChrome {
    static let css = """
    body.theme-kde.theme-win98, body.theme-kde.theme-win98 .w98-menubar, body.theme-kde.theme-win98 .np-status,
    body.theme-kde.theme-win98 .w98-menubar span, body.theme-kde.theme-win98 .menu, body.theme-kde.theme-win98 .w98-mi {
      font-family:Helvetica,Arial,sans-serif!important; }
    body.theme-kde.theme-win98 .w98-title { background:linear-gradient(to right,#000080,#000000)!important; }
    body.theme-kde.theme-win98 .w98-cap { font:700 12px Helvetica,Arial,sans-serif!important; color:#FFF!important; }
    body.theme-kde.theme-win98 #win { padding:4px!important; }
    """

    /// Marks the page as KDE and lays the repaint over its Windows 98 chrome.
    static let js = "(function(){var e=document.getElementById('w98scheme'); if(e) e.remove(); document.body.classList.add('theme-kde');"
        + " var st=document.createElement('style'); st.id='w98scheme'; st.textContent=`\(css)`; document.head.appendChild(st);})();"
}
