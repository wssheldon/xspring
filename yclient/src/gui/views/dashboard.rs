use crate::gui::client::GuiClient;
use egui::Ui;

impl GuiClient {
    /// Render the dashboard view
    pub fn render_dashboard_view(&mut self, ui: &mut Ui) {
        ui.heading("Dashboard");
        ui.separator();

        ui.add_space(20.0);
        ui.label("Welcome to XClient Dashboard");
        ui.add_space(10.0);

        // Show statistics about connected beacons
        if let Ok(beacons) = self.beacons.lock() {
            let active_count = beacons.iter().filter(|b| b.status == "active").count();
            let total_count = beacons.len();

            ui.horizontal(|ui| {
                ui.label("Connected beacons:");
                ui.strong(format!("{} (Total: {})", active_count, total_count));
            });
        }

        // Placeholder for future dashboard components
        ui.add_space(20.0);
        ui.label("Dashboard functionality will be expanded in future versions");
    }
}
