use crate::gui::client::GuiClient;
use crate::models::Tab;
use egui_dock::TabViewer;

/// Implementation of the TabViewer trait for GuiClient to enable tabbed interface
impl TabViewer for GuiClient {
    type Tab = Tab;

    fn ui(&mut self, ui: &mut egui::Ui, tab: &mut Self::Tab) {
        match tab {
            Tab::Beacon(beacon_id) => {
                // Find or create session for this beacon
                let session_idx = self.find_or_create_session(beacon_id);

                // Show the beacon command interface
                self.render_beacon_session(ui, session_idx);
            }
        }
    }

    fn title(&mut self, tab: &mut Self::Tab) -> egui::WidgetText {
        match tab {
            Tab::Beacon(beacon_id) => beacon_id.clone().into(),
        }
    }

    fn on_close(&mut self, tab: &mut Self::Tab) -> bool {
        match tab {
            Tab::Beacon(beacon_id) => {
                // Find and remove the session
                if let Some(idx) = self
                    .active_sessions
                    .iter()
                    .position(|s| &s.beacon_id == beacon_id)
                {
                    self.active_sessions.remove(idx);
                }
                true // Allow the tab to close
            }
        }
    }
}

/// Struct for simple tab implementation that avoids borrow checker issues
#[derive(Clone)]
pub struct SimpleTab {
    pub id: String,
}

/// TabViewer implementation for SimpleTab that references the GuiClient
pub struct SimpleTabViewer<'a>(&'a mut GuiClient);

impl<'a> TabViewer for SimpleTabViewer<'a> {
    type Tab = SimpleTab;

    fn title(&mut self, tab: &mut Self::Tab) -> egui::WidgetText {
        tab.id.clone().into()
    }

    fn ui(&mut self, ui: &mut egui::Ui, tab: &mut Self::Tab) {
        let session_idx = self.0.find_or_create_session(&tab.id);
        self.0.render_beacon_session(ui, session_idx);
    }

    fn on_close(&mut self, tab: &mut Self::Tab) -> bool {
        if let Some(idx) = self
            .0
            .active_sessions
            .iter()
            .position(|s| &s.beacon_id == &tab.id)
        {
            self.0.active_sessions.remove(idx);
        }
        true
    }
}
