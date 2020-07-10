#
# bot class
#

require "mumble-ruby"
require "sqlite3"

class Bot
    def initialize()
        puts "Initializing bot."

        printf "Connecting to database: %s\n", Settings.database_path
        @db = SQLite3::Database.new Settings.database_path

        puts "Initializing tables."

        @db.execute "CREATE TABLE IF NOT EXISTS links ( id INT PRIMARY KEY, author TEXT NOT NULL, timestamp"

        @db.execute %{
            CREATE TABLE IF NOT EXISTS links (
                author TEXT NOT NULL,
                timestamp DATETIME NOT NULL,
            )
        }

        @db.execute %{
            CREATE TABLE IF NOT EXISTS sounds (
                soundname TEXT NOT NULL UNIQUE,
                author TEXT NOT NULL,
                timestamp DATETIME NOT NULL,
            )
        }

        @db.execute %{
            CREATE TABLE IF NOT EXISTS aliases (
                commandname TEXT NOT NULL UNIQUE,
                soundname TEXT NOT NULL,
                author TEXT NOT NULL,
                timestamp DATETIME NOT NULL,
            )
        }

        @conn = Mumble::Client.new(Settings.host) do |conf|
            conf.username = Settings.name
            conf.password = Settings.password
            conf.bitrate = Settings.bitrate
            conf.sample_rate = Settings.samplerate
            conf.ssl_cert_opts[:cert_dir] = File.expand_path("./certs")
        end

        @conn.on_connected do
            printf "Connected to Mumble server as %s.\n", Settings.name

            @conn.join_channel(Settings.channel)
            printf "Joined channel %s.\n", Settings.channel

#            @conn.player.stream_named_pipe(Settings.pipe)
#            printf "Streaming audio from %s.\n", Settings.pipe

            @conn.on_text_message do |msg| self.on_text_message msg end
            @conn.on_user_state do |state| self.on_user_state state end
            puts "Initialized callbacks."
        end

        printf "Connecting to %s.\n", Settings.host
        @conn.connect
    end

    def on_text_message(msg)
      printf "%s: %s\n", @conn.users[msg.actor].name, msg.message
    end

    def on_user_state(state)
    end
end
