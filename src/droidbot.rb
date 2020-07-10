#
# droidbot entry point
#

require 'config'
require_relative 'bot'

PROMPT = '=> '

# initialize config
Config.load_and_set_settings("defaults.yml", "config.yml")

# initialize bot
bot = Bot.new

print PROMPT
while input = gets.chomp do
    print PROMPT
end
