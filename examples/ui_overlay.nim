## Optional composition proof with nc568/fossil-nim uirelays-web-backends.
## Build with -d:html --path:/path/to/fossil-nim/src. UI has separate DOM ownership.
import browser
import uirelays

discard createWindow(800, 600)
var metrics: FontMetrics
let font = openFont("", 18, metrics)
fillRect(rect(16, 16, 310, 54), color(25, 35, 45))
discard drawText(font, 28, 30, "UIRelays + Nim WebGL", color(240, 245, 255), color(0, 0, 0, 0))
refresh()
closeFont(font)
