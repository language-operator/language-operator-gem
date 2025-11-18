require 'language_operator'

agent "001" do
  description "Continuously logs a message to stdout"

  task :generate_message do |inputs|
    { message: "Agent 001 active at iteration #{inputs[:iteration]}" }
  end

  main do |inputs|
    current_iteration = inputs[:iteration] || 0
    message_data = execute_task(:generate_message, inputs: { iteration: current_iteration })
    {
      iteration: current_iteration + 1,
      message: message_data[:message]
    }
  end

  constraints do
    max_iterations 999999
    timeout "10m"
  end

  output do |outputs|
    puts outputs[:message]
  end
end
