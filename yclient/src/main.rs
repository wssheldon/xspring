use colored::*;
use rustyline::error::ReadlineError;
use rustyline::{DefaultEditor, Result};
use std::path::PathBuf;

struct Client {
    editor: DefaultEditor,
    history_path: PathBuf,
    server_url: String,
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
        println!("  {} - Show this help message", "help".cyan());
        println!("  {} - Clear the screen", "clear".cyan());
        println!("  {} - Exit the client", "exit".cyan());
        println!();
    }

    fn handle_command(&self, command: &str) -> bool {
        match command.trim() {
            "exit" | "quit" => {
                println!("{}", "Goodbye!".green());
                return false;
            }
            "help" => self.print_help(),
            "clear" => print!("\x1B[2J\x1B[1;1H"), // Clear screen
            "ping" => self.send_ping(),
            "" => (),
            cmd => println!("{} {}", "Unknown command:".red(), cmd),
        }
        true
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
}

fn main() -> Result<()> {
    let mut client = Client::new()?;
    client.run()
}
