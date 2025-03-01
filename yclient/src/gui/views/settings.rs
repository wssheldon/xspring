use crate::gui::client::GuiClient;
use egui::Ui;

impl GuiClient {
    /// Render the settings view
    pub fn render_settings_view(&mut self, ui: &mut Ui) {
        ui.heading("Settings");
        ui.separator();

        ui.add_space(20.0);

        // Server settings
        ui.collapsing("Server Connection", |ui| {
            ui.horizontal(|ui| {
                ui.label("Server URL:");
                ui.text_edit_singleline(&mut self.server_url.clone());
            });
            if ui.button("Apply").clicked() {
                // TODO: Implement settings application
            }
        });

        // Theme settings (placeholder)
        ui.collapsing("Theme", |ui| {
            ui.label("Theme settings will be added in a future release.");
        });

        // About section
        ui.collapsing("About", |ui| {
            ui.label("XClient - A command and control client");
            ui.label("Version: 0.1.0");
        });
    }
}
