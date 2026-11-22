import AppKit
let size=NSSize(width:640,height:400)
let image=NSImage(size:size)
image.lockFocus()
GuideDrawing.paper.setFill();NSRect(origin:.zero,size:size).fill()
let ink=GuideDrawing.ink
func text(_ value:String,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight) {
    let style=NSMutableParagraphStyle();style.alignment = .center
    (value as NSString).draw(in:NSRect(x:20,y:y,width:600,height:45),withAttributes:[
        .font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:ink,.paragraphStyle:style])
}
text("Sage Keys",315,32,.medium)
text("Sage Keys  →  Applications",275,17,.regular)
text("拖入右邊資料夾，完成安裝",83,16,.medium)
text("更新前請先退出正在運行的 Sage Keys",48,13,.regular)
let arrow=NSBezierPath()
arrow.move(to:NSPoint(x:265,y:204));arrow.curve(to:NSPoint(x:374,y:204),controlPoint1:NSPoint(x:300,y:224),controlPoint2:NSPoint(x:345,y:188))
arrow.lineWidth=2;arrow.setLineDash([4,6],count:2,phase:0);ink.setStroke();arrow.stroke()
let tip=NSBezierPath();tip.move(to:NSPoint(x:362,y:211));tip.line(to:NSPoint(x:375,y:204));tip.line(to:NSPoint(x:364,y:197));tip.lineWidth=2;tip.stroke()
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
