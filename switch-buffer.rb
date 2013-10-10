#!/usr/bin/ruby
# vim: set fileencoding=utf-8 :

# This script is inspired by "im_typing_notice" for irssi.
# It creates a new bar item displaying when contacts are typing on supported protocol in minbif
# It sends a notice to your contacts when you're typing a message.
#
# Author: CissWit cisswit at 6-8 dot fr
# Version 1.0.1
#
# Changelog :
#
# * 1.0.1
#   Ignore the user "request" (no need to tell it we are typing)
#
# * 1.0
#   Original version
#
# Licence GPL3

require 'shellwords'

TMPFILE_IN = '/tmp/xmosh/weechat-buffers-in'
TMPFILE_OUT = '/tmp/xmosh/weechat-buffers-out'

def weechat_init
  Weechat.register(
    "switch-buffer",
    "anekos",
    "1.0.0",
    "GPL3",
    "Switch buffer with percol.",
    "",
    "utf-8"
  )

  Weechat.hook_command(
    "percolbuffer",
    "Switch buffer with percol.",
    "", # args
    "", # args_description
    "", # completion
    "switch_buffer",
    ""
  )

  File.write(TMPFILE_OUT, '')

  return Weechat::WEECHAT_RC_OK
end

def switch_buffer (data, buffer, args)
  bs = buffer_list

  #puts bs.join("\n")
  #return Weechat::WEECHAT_RC_OK

  current = Weechat.buffer_get_string(Weechat.current_buffer, 'name')
  ecurrent = Shellwords.shellescape(current)
  index = bs.map(&:name).index(current) || 0

  File.write(TMPFILE_IN, bs.map {|b| "%.2d %s" % [b.number, b.name] } .join("\n"))
  `tmux split-window 'cat #{TMPFILE_IN} | (percol --match-method=migemo --initial-index=#{index}; echo "#{current}") > #{TMPFILE_OUT}'`

  a, b = File.mtime(TMPFILE_OUT), File.size(TMPFILE_OUT)
  sleep 0.2 while File.mtime(TMPFILE_OUT) == a or File.size(TMPFILE_OUT) == 0

  to = File.read(TMPFILE_OUT).split("\n").first
  Weechat.command('', "/buffer #{to}")

  return Weechat::WEECHAT_RC_OK
end

def buffer_list
  result = []
  infolist = Weechat.infolist_get('buffer', '', '')
  while Weechat.infolist_next(infolist) == 1
    name = Weechat.infolist_string(infolist, 'name')
    num = Weechat.infolist_integer(infolist, 'number')
    result << Struct.new(:name, :number).new(name, num)
  end
  Weechat.infolist_free(infolist)
  result
end

__END__

def weechat_init
  Weechat.bar_item_new("typing_notice", "draw_typing", "")
  Weechat.hook_modifier("irc_in_privmsg", "modifier_ctcp", "")
  Weechat.hook_signal("input_text_changed", "input_changed", "")
  if Weechat.config_is_set_plugin("minbif_server") == 0
    Weechat.config_set_plugin("minbif_server", "minbif")
  end
  Weechat.print("", "typing_notice: minbif typing notice")
  Weechat.print("", "typing_notice: Put [typing_notice] in your status bar (or the one you prefer) to show when contacts are typing message to you.")
  return Weechat::WEECHAT_RC_OK
end

def input_changed(data,signal,type_data)
  buffer = Weechat.current_buffer
  buffer_name = Weechat.buffer_get_string buffer, "name"

  if buffer_name =~ /^#{Weechat.config_get_plugin("minbif_server")}\.(.*)/
    nick = $1
    if nick == "request"
      return Weechat::WEECHAT_RC_OK
    end

    buffer_text = Weechat.buffer_get_string(buffer,"input")
    if(buffer_text == "" or buffer_text =~ /^\//)
      if $h_sending.key?(buffer)
        Weechat.command(buffer,"/mute all ctcp #{nick} TYPING 0")
        Weechat.unhook($h_sending[buffer]["timer"])
        $h_sending.delete(buffer)
      end
      return Weechat::WEECHAT_RC_OK
    end

    return Weechat::WEECHAT_RC_OK unless !$h_sending.key?(buffer)
    Weechat.command(buffer,"/mute -all ctcp #{nick} TYPING 1")
    if $h_sending.key?(buffer)
      Weechat.unhook($h_sending[buffer]["timer"])
    else
      $h_sending[buffer] = Hash.new
    end
    $h_sending[buffer]["timer"] = Weechat.hook_timer(7000,0,1,"sending_timeout",buffer)
    $h_sending[buffer]["time"] = Time.new
  end
  return Weechat::WEECHAT_RC_OK
end

def sending_timeout(buffer,n)
  if $h_sending.key?(buffer)
    buffer_name = Weechat.buffer_get_string buffer, "name"
    if buffer_name =~ /^#{Weechat.config_get_plugin("minbif_server")}\.(.*)/
      Weechat.command(buffer,"/mute -all ctcp #{$1} TYPING 0")
      Weechat.unhook($h_sending[buffer]["timer"])
      $h_sending.delete(buffer)
    end
  end
  return Weechat::WEECHAT_RC_OK
end

def draw_typing(osefa,osefb,osefc)
  buffer = Weechat.current_buffer
  if $h_typing.key?(buffer)
    return "TYPING"
  end
  return ""
end

def typing_timeout(buffer,n)
  if $h_typing.key?(buffer)
    Weechat.unhook($h_typing[buffer])
    $h_typing.delete(buffer)
  end
  Weechat.bar_item_update("typing_notice")
end

def modifier_ctcp(data, modifier, modifier_data, string)
  if string =~ /:([^!]*)!([^\s]*)\sPRIVMSG\s([^\s]*)\s:\01TYPING\s([0-9])\01/
    buffer = Weechat.buffer_search("irc", modifier_data + "." + $1)
    if $h_typing.key?(buffer)
      Weechat.unhook($h_typing[buffer])
    end
    if $4 == "1"
      $h_typing[buffer] = Weechat.hook_timer(7000,0,1,"typing_timeout",buffer)
    elsif $4 == "0"
      if $h_typing.key?(buffer)
        $h_typing.delete(buffer)
      end
    elsif $4 == "2"
      Weechat.print("","- #{$4} - #{$1} - #{buffer} - is typing")
    end
    Weechat.bar_item_update("typing_notice")
    return ""
  end
  return string
end

