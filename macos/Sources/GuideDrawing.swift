import AppKit

enum GuideIllustration {case status, settings, repair, replace, success, installation}

// Original pen-and-wash illustrations. No animation, textures or GPU context.
final class GuideDrawing: NSView {
    let page: GuideIllustration
    static let ink = NSColor(srgbRed:0.17,green:0.26,blue:0.20,alpha:1)
    static let paper = NSColor(srgbRed:0.975,green:0.967,blue:0.925,alpha:1)
    private let sage = NSColor(srgbRed:0.70,green:0.78,blue:0.66,alpha:1)
    private let mint = NSColor(srgbRed:0.86,green:0.90,blue:0.80,alpha:1)
    private let cream = NSColor(srgbRed:1.0,green:0.985,blue:0.92,alpha:1)
    private let gold = NSColor(srgbRed:0.91,green:0.79,blue:0.54,alpha:1)
    override var isFlipped: Bool {true}
    init(_ page: GuideIllustration) {
        self.page=page;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.image)
        switch page {
        case .status: setAccessibilityLabel("小鍵盤旁的鎖上有問號，權限待核對")
        case .settings: setAccessibilityLabel("設定示意圖：從私隱與保安找到輸入監察及 Sage Keys 開關")
        case .repair,.installation: setAccessibilityLabel("放大鏡核對兩份 App 的安裝身分")
        case .replace: setAccessibilityLabel("先移除失效的 Sage Keys 項目，再用加號加入目前版本")
        case .success: setAccessibilityLabel("小鍵盤旁有綠色勾號，權限檢查通過")
        }
    }
    required init?(coder:NSCoder){fatalError()}
    private func path(_ points:[NSPoint], fill:NSColor?=nil, width:CGFloat=1.7) {
        guard let first=points.first else{return}
        let p=NSBezierPath();p.move(to:first)
        for v in points.dropFirst(){p.line(to:v)}
        if let fill=fill {p.close();fill.setFill();p.fill()}
        p.lineWidth=width;p.lineJoinStyle = .round;p.lineCapStyle = .round;Self.ink.setStroke();p.stroke()
    }
    private func rect(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ r:CGFloat,_ color:NSColor,_ width:CGFloat=1.6){
        let p=NSBezierPath(roundedRect:NSRect(x:x,y:y,width:w,height:h),xRadius:r,yRadius:r)
        color.setFill();p.fill();p.lineWidth=width;Self.ink.setStroke();p.stroke()
    }
    private func oval(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ color:NSColor,outline:Bool=true) {
        let p=NSBezierPath(ovalIn:NSRect(x:x,y:y,width:w,height:h));color.setFill();p.fill()
        if outline {Self.ink.setStroke();p.lineWidth=1.7;p.stroke()}
    }
    private func curve(_ a:NSPoint,_ b:NSPoint,_ c:NSPoint,_ end:NSPoint,dots:Bool=false) {
        let p=NSBezierPath();p.move(to:a);p.curve(to:end,controlPoint1:b,controlPoint2:c)
        p.lineWidth=1.8;p.lineCapStyle = .round
        if dots {p.setLineDash([3,5],count:2,phase:0)}
        Self.ink.setStroke();p.stroke()
    }
    #if SAGE_QA
    static var qaPaints = 0
    #endif
    override func draw(_ dirtyRect:NSRect) {
        #if SAGE_QA
        Self.qaPaints += 1
        #endif
        guard let cg=NSGraphicsContext.current?.cgContext else{return}
        let P: (CGFloat,CGFloat) -> NSPoint = {NSPoint(x:$0,y:$1)}
        let bg=NSBezierPath(roundedRect:bounds,xRadius:13,yRadius:13)
        mint.withAlphaComponent(0.65).setFill();bg.fill()
        cg.saveGState()
        let scale=min(bounds.width/408,bounds.height/120)
        cg.translateBy(x:(bounds.width-408*scale)/2,y:(bounds.height-120*scale)/2);cg.scaleBy(x:scale,y:scale)
        // A keyboard in shallow perspective, a graphite edge, small raised caps and a smile.
        cg.saveGState();cg.translateBy(x:44,y:35);cg.rotate(by:-0.065)
        path([P(4,11),P(137,9),P(153,50),P(148,58),P(0,59),P(-4,53)],fill:sage)
        path([P(5,6),P(134,4),P(149,47),P(-3,49)],fill:cream)
        for r in 0..<3 {
            for c in 0..<(r==2 ? 6:10) {
                let x=CGFloat(c*12+8)+CGFloat(r)*0.8, y=CGFloat(r*9+10)
                rect(x,y,9,6.2,1.4,(c+r)%4==0 ? sage:mint,0.9)
            }
        }
        rect(21,37,67,6,2,mint,1.0);rect(95,36,12,6,1.4,sage,1.0)
        oval(111,34,3.2,4,Self.ink,outline:false);oval(129,33,3.2,4,Self.ink,outline:false)
        curve(P(117,38),P(119,42),P(123,42),P(125,37))
        path([P(18,59),P(16,65),P(9,65)],width:2);path([P(119,57),P(122,63),P(130,63)],width:2)
        cg.restoreGState()
        curve(P(202,62),P(222,39),P(244,79),P(266,51),dots:true)
        path([P(256,52),P(267,49),P(266,59)])
        switch page {
        case .status:
            curve(P(305,57),P(299,9),P(344,9),P(340,54))
            rect(295,48,55,45,8,gold)
            curve(P(314,62),P(322,46),P(340,64),P(323,70))
            path([P(323,70),P(322,76)]);oval(320,80,3.2,3.2,Self.ink,outline:false)
        case .settings:
            rect(280,25,86,66,6,cream);path([P(280,39),P(366,39)],width:1.1)
            for c in 0..<3 {oval(CGFloat(287+c*6),30,2.7,2.7,sage,outline:false)}
            path([P(290,52),P(310,51)]);path([P(290,66),P(313,65)])
            rect(324,57,30,15,7,mint);oval(326,59,11,11,cream)
        case .repair,.installation:
            rect(280,22,46,53,5,mint);rect(295,31,46,54,5,cream)
            rect(304,43,27,18,3,sage);path([P(307,51),P(326,50)],width:1.1)
            oval(321,51,31,30,cream.withAlphaComponent(0.76));path([P(346,78),P(360,94)],width:4)
        case .replace:
            rect(279,26,87,60,6,cream);path([P(279,40),P(366,40)],width:1)
            rect(287,48,52,11,2,mint,1)
            path([P(292,72),P(302,72)]);path([P(315,72),P(325,72)]);path([P(320,67),P(320,77)])
            curve(P(350,89),P(344,94),P(328,92),P(321,81),dots:true)
        case .success:
            oval(292,27,61,60,sage);path([P(306,57),P(318,68),P(340,43)],width:3.6)
            curve(P(340,32),P(345,16),P(355,19),P(356,17));path([P(348,30),P(359,25)])
        }
        cg.restoreGState()
    }
}
