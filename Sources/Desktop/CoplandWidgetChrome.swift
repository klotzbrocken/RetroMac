import Foundation

/// RetroMac's own windows (Applications, Calculator, Notepad, Clock, CPU) under the Copland
/// theme. Their pages draw Mac OS 9's Platinum; this lays Copland D11E4's own pieces over it —
/// the title bar boxes, the scroll arrows and the lavender thumbs from the StandardTheme `pixs`
/// (`Resources/Chrome/copland`) — and makes an inactive window flat and box-less, as D11E4 drew
/// it. Injected like a Windows 98 scheme, as the page's `#w98scheme` style.
enum CoplandWidgetChrome {

    static var js: String {
        let css = """
        body.theme-macos9 .m9-close,body.theme-macos9 .m9-zoom,body.theme-macos9 .m9-collapse{width:13px!important;height:13px!important;
          border:none!important;box-shadow:none!important;image-rendering:pixelated;background-size:13px 13px!important;background-repeat:no-repeat!important;}
        body.theme-macos9 .m9-close{background-image:\(url("close"))!important;margin:3px 0 0 4px!important;}
        body.theme-macos9 .m9-zoom{background-image:\(url("zoom"))!important;margin:3px 3px 0 0!important;}
        body.theme-macos9 .m9-collapse{background-image:\(url("collapse"))!important;margin:3px 4px 0 3px!important;}
        body.theme-macos9 .m9-close:active{background-image:\(url("close-active"))!important;}
        body.theme-macos9 .m9-zoom:active{background-image:\(url("zoom-active"))!important;}
        body.theme-macos9 .m9-collapse:active{background-image:\(url("collapse-active"))!important;}
        body.theme-macos9 .m9-zoom::before,body.theme-macos9 .m9-zoom::after,
        body.theme-macos9 .m9-collapse::before,body.theme-macos9 .m9-collapse::after{content:none!important;}
        body.theme-macos9.rm-blur .m9-close,body.theme-macos9.rm-blur .m9-zoom,body.theme-macos9.rm-blur .m9-collapse{visibility:hidden!important;}
        body.theme-macos9.rm-blur .m9-title{background:#dadada!important;}
        body.theme-macos9 .sb-btn{border:none!important;box-shadow:none!important;image-rendering:pixelated;
          background-size:100% 100%!important;background-repeat:no-repeat!important;}
        body.theme-macos9 .sb-btn[data-v="-1"]{background-image:\(url("sb-up"))!important;}
        body.theme-macos9 .sb-btn[data-v="1"]{background-image:\(url("sb-down"))!important;}
        body.theme-macos9 .sb-btn[data-h="-1"]{background-image:\(url("sb-left"))!important;}
        body.theme-macos9 .sb-btn[data-h="1"]{background-image:\(url("sb-right"))!important;}
        body.theme-macos9 .sb-btn[data-v="-1"]:active{background-image:\(url("sb-up-active"))!important;}
        body.theme-macos9 .sb-btn[data-v="1"]:active{background-image:\(url("sb-down-active"))!important;}
        body.theme-macos9 .sb-btn[data-h="-1"]:active{background-image:\(url("sb-left-active"))!important;}
        body.theme-macos9 .sb-btn[data-h="1"]:active{background-image:\(url("sb-right-active"))!important;}
        body.theme-macos9 .sb-trough{background:#eeeeee!important;}
        body.theme-macos9 .vsb .sb-arrows:first-child .sb-btn[data-v="1"],body.theme-macos9 .vsb .sb-arrows:last-child .sb-btn[data-v="-1"],
        body.theme-macos9 .hsb .sb-arrows:first-child .sb-btn[data-h="1"],body.theme-macos9 .hsb .sb-arrows:last-child .sb-btn[data-h="-1"]{display:none!important;}
        body.theme-macos9 .sb-thumb{border:none!important;box-shadow:none!important;image-rendering:pixelated;}
        body.theme-macos9 .sb-thumb[data-thumb="v"]{background:\(url("sb-thumb-v")) center/16px 19px no-repeat!important;}
        body.theme-macos9 .sb-thumb[data-thumb="h"]{background:\(url("sb-thumb-h")) center/19px 16px no-repeat!important;}
        body.theme-macos9 .sb-thumb::before,body.theme-macos9 .sb-thumb::after{content:none!important;}
        body.theme-macos9 .sb-idle .sb-thumb{display:none!important;}
        """
        let literal = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
        return """
        (function(){var e=document.getElementById('w98scheme'); if(e) e.remove();
          var s=document.createElement('style'); s.id='w98scheme'; s.textContent=`\(literal)`;
          document.head.appendChild(s);})();
        """
    }

    /// A part as a data URL: the pages may only read their own folder.
    private static func url(_ name: String) -> String {
        if let cached = cache[name] { return cached }
        let file = Bundle.main.resourceURL?.appendingPathComponent("Chrome/copland/\(name).png")
        let value = file.flatMap { try? Data(contentsOf: $0) }.map { "url(data:image/png;base64,\($0.base64EncodedString()))" } ?? "none"
        cache[name] = value
        return value
    }
    private static var cache: [String: String] = [:]
}
