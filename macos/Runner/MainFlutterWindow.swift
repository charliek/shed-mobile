import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app renders the desktop sidebar layout at >= 900pt and the mobile
    // layout below it, so open wide and never let the content shrink under the
    // breakpoint.
    self.setContentSize(NSSize(width: 1180, height: 820))
    self.contentMinSize = NSSize(width: 940, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
