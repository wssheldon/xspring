impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // ... existing code ...
    }

    fn setup(
        &mut self,
        ctx: &egui::Context,
        _frame: &mut eframe::Frame,
        _storage: Option<&dyn eframe::Storage>,
    ) {
        // Initialize Phosphor icons
        let mut fonts = egui::FontDefinitions::default();
        egui_phosphor::add_to_fonts(&mut fonts, egui_phosphor::Variant::Regular);
        ctx.set_fonts(fonts);

        // ... rest of setup code if any ...
    }
}
