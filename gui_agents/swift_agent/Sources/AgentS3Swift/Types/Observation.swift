import Foundation

/// Observation structure containing screenshot data
struct Observation: Codable {
    var screenshot: Data  // PNG image bytes
    
    init(screenshot: Data) {
        self.screenshot = screenshot
    }
}
