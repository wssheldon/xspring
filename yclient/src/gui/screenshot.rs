use crate::models::Tab;
use egui_dock::DockState;

pub trait ScreenshotHandler {
    fn open_screenshot_tab(&mut self, screenshot_data: String);
}
