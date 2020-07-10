#
# bot class
#

require "uri"
require "mumble-ruby"
require "sqlite3"
require "ruby-mpd"

$help_text = %{
Commands: <br>
<table>
  <tr>
    <th>Command</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>!alias</td>
    <td>Create a command alias.</td>
  </tr>
  <tr>
    <td>!aliases</td>
    <td>List existing aliases.</td>
  </tr>
  <tr>
    <td>!delalias</td>
    <td>Delete an alias.</td>
  </tr>
  <tr>
    <td>!grab</td>
    <td>Create a soundclip from a part of a video.</td>
  </tr>
  <tr>
    <td>!link</td>
    <td>Get a random saved link.</td>
  </tr>
  <tr>
    <td>!ping</td>
    <td>Basic ping test. Responds with "Pong!"</td>
  </tr>
  <tr>
    <td>!stats</td>
    <td>View database statistics</td>
  </tr>
</table>
}

class Bot
    def initialize()
        puts "Initializing bot."

        printf "Connecting to MPD at %s:%d\n", Settings.mpd_host, Settings.mpd_port
        @mpd = MPD.new Settings.mpd_host, Settings.mpd_port
        @mpd.connect
        puts "Connected to MPD."

        printf "Connecting to database at %s\n", Settings.database_path
        @db = SQLite3::Database.new Settings.database_path
        puts "Connected to database."

        puts "Initializing tables."

        @db.execute %{
            CREATE TABLE IF NOT EXISTS links (
                author TEXT NOT NULL,
                dest TEXT UNIQUE NOT NULL,
                timestamp DATETIME NOT NULL
            )
        }

        @db.execute %{
            CREATE TABLE IF NOT EXISTS sounds (
                soundname TEXT NOT NULL UNIQUE,
                author TEXT NOT NULL,
                timestamp DATETIME NOT NULL
            )
        }

        @db.execute %{
            CREATE TABLE IF NOT EXISTS aliases (
                commandname TEXT NOT NULL UNIQUE,
                action TEXT NOT NULL,
                author TEXT NOT NULL,
                timestamp DATETIME NOT NULL
            )
        }

        puts "Tables ready."

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

            @conn.on_text_message do |msg| self.on_text_message msg end
            @conn.on_user_state do |state| self.on_user_state state end
            puts "Initialized callbacks."

            puts "Starting audio stream.."
            @conn.player.stream_named_pipe("mpd.fifo")
            puts "Started audio stream."
        end

        printf "Connecting to %s.\n", Settings.host
        @conn.connect
    end

    def on_text_message(msg, alias_depth = 0)
      sender = @conn.users[msg.actor].name

      # Strip noise from the message and extract plaintext.
      msg.message = msg.message.chomp.sub /<[^>]*>/, ''

      if msg.message.start_with? '!'
        args = msg.message.split ' '
        args[0].slice!(0)

        methname = "handle_" + args[0]

        if self.respond_to? methname
          return self.send(methname, args, sender)
        else
          matches = @db.execute "SELECT action FROM aliases WHERE commandname=?", [args[0]]

          if matches.length == 1
            if alias_depth > 16
              @conn.text_channel_img(Settings.channel, 'res/alias_depth_warning.jpg')
            else
              msg.message = matches[0][0]
              puts 'Executing alias: %s => %s' % [args[0], msg.message]
              return self.on_text_message msg, alias_depth + 1
            end
          end
        end

        @conn.text_user(sender, 'Unknown command %s.' % [args[0]])
      end

      # Grab links if not dispatched into a command.
      URI::extract(msg.message, ['http', 'https']).uniq.each do |entry|
        puts 'Extracted link: %s' % [entry]
        @db.execute "INSERT INTO links VALUES (?, ?, datetime('now'))", [sender, entry]
      end
    end

    def on_user_state(state)
      self.handle_play 'self', ['!play']
    end

    def create_alias(commandname, targetname, author)
      # Returns false if the alias already exists."
      if @db.execute("SELECT * FROM aliases WHERE commandname=?", [commandname]).length > 0
        return false
      else
        @db.execute "INSERT INTO aliases VALUES (?, ?, ?, datetime('now'))", [commandname, targetname, author]
      end
    end

    def handle_ping(args, sender)
      @conn.text_user(sender, "Pong!")
    end

    def handle_alias(args, sender)
      if args.length < 3
        @conn.text_user(sender, "usage: %s [alias] [action]" % [args[0]])
        return
      end

      action = args[2..].join ' '

      if self.create_alias args[1], action, sender
        @conn.text_user(sender, "Created alias \"%s\" => \"%s\"." % [args[1], args[2]])
      else
        @conn.text_user(sender, "Alias \"%s\" already exists!" % [args[1]])
      end
    end

    def handle_stats(args, sender)
      total_links = (@db.execute "SELECT COUNT(*) FROM links")[0][0]
      total_sounds = (@db.execute "SELECT COUNT(*) FROM sounds")[0][0]

      p total_links, total_sounds

      @conn.text_user(sender, "Stats:<br>Total links: %d<br>Total sounds: %d<br>" % [total_links, total_sounds])
    end

    def handle_get(args, sender)
      if args.length != 4
        return @conn.text_user(sender, "usage: !%s [url] [start] [length]" % [args[0]])
      end

      targetname = SecureRandom.hex[0..11]
      result = system("scripts/grab_yt.sh \"#{args[1]}\" \"#{args[2]}\" \"#{args[3]}\" \"#{targetname}\"")

      if result
        # Sound downloaded OK, so insert the new entry into the db.
        @db.execute "INSERT INTO sounds VALUES (?, ?, datetime('now'))", [targetname, sender]

        # Update mpd database as well.
        @mpd.update

        @conn.text_user(sender, "Grabbed video with new ID #{targetname}")

        # Play the new sound.
        self.handle_play(["!play", targetname], sender)
      else
        @conn.text_user(sender, "Error occurred during grab.")
      end
    end

    def handle_play(args, sender)
      to_play = @db.execute("SELECT soundname FROM sounds ORDER BY RANDOM() LIMIT 1")[0][0]

      if to_play.length == 0
        @conn.text_user(sender, "No sounds to play!")
        return
      end

      if args.length >= 2
        to_play = args[1]
      end

      # Try and locate the sound in the mpd playlist.
      results = @mpd.where({file: "#{to_play}.mp3"})

      if results.length == 1
        @mpd.clear
        @mpd.add results[0]
        @mpd.play
      else
        if results.length > 1
          puts "warning: #{results.length} results for MPD search for #{to_play}"
        end

        @conn.text_user(sender, "#{to_play} not found.")
      end
    end

    def handle_link(args, sender)
      res = @db.execute "SELECT rowid, * FROM links ORDER BY RANDOM() LIMIT 1"

      if res.length == 0
        @conn.msg_user(sender, "No links to choose from!")
        return
      end

      id = res[0][0]
      dest = res[0][2]

      link_text = [
        "It's link season",
        "I bring these links for you",
        "Nice.",
      ].sample

      @conn.text_channel(Settings.channel, "%d: <a href=\"%s\">%s</a>" % [id, dest, link_text])
    end

    def handle_aliases(args, sender)
      resp = "Aliases:<br><table><tr><th>Alias</th><th>Action</th><th>Author</th><th>Created</th></tr>"

      @db.execute("SELECT * FROM aliases ORDER BY commandname") do |row|
        resp = resp + "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % row
      end

      @conn.text_user(sender, resp + "</table>")
    end

    def handle_sounds(args, sender)
      resp = "Sounds:<br><table><tr><th>ID</th><th>Author</th><th>Created</th></tr>"

      @db.execute("SELECT * FROM sounds ORDER BY timestamp") do |row|
        resp = resp + "<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % row
      end

      @conn.text_user(sender, resp + "</table>")
    end

    def handle_delalias(args, sender)
      if args.length != 2
        @conn.text_user("usage: %s [alias]" % [args[0]])
        return
      end

      p @db.execute "DELETE FROM aliases WHERE commandname=?", args[1]
    end

    def handle_help(args, sender)
      @conn.text_user(sender, $help_text)
    end
end
