# An SMTP server implementation that just echoes what it 
# gets from clients to STDOUT. Useful for testing that mails get sent.
# ---
# Takes a single optional argument that is the port to listen on (default is 2525).

require 'socket'

port = ARGV[0] || 2525
puts "Binding to port #{port}"
server = TCPServer.open port

loop do
  client = server.accept
  puts 'SERVER INFO: SMTP client connected!'
  client.puts "220 Awesome SMTP server\r\n"
  connected = true
  reading_data = false
  while connected
    line = client.gets
    puts line
    case line
    when "DATA\r\n"
      reading_data = true
      client.puts "354 Intermediate\r\n"
    when ".\r\n"
      reading_data = false
      client.puts "250 OK\r\n"
    when "QUIT\r\n"
      connected = false
    else
      client.puts "250 OK\r\n" unless reading_data
    end
  end
  client.close
  puts 'SERVER INFO: SMTP client disconnected!'
end
