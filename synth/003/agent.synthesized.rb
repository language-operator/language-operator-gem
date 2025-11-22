require 'language_operator'

agent "s003" do
  description "Build a story one sentence at a time, with one new sentence every hour"
  mode :scheduled
  schedule "0 * * * *"

  task :read_existing_story,
    instructions: "Read the story.txt file from workspace. If it doesn't exist, return empty string. Return the content and count of sentences.",
    inputs: {},
    outputs: { content: 'string', sentence_count: 'integer' }

  task :generate_next_sentence,
    instructions: "Generate exactly one new sentence to continue this story. Maintain consistent tone and style. Only output the new sentence.",
    inputs: { existing_content: 'string' },
    outputs: { sentence: 'string' }

  task :append_to_story,
    instructions: "Append the new sentence to story.txt in workspace. If the file has existing content, add a newline first.",
    inputs: { sentence: 'string' },
    outputs: { success: 'boolean', total_sentences: 'integer' }

  main do |inputs|
    story_data = execute_task(:read_existing_story)
    new_sentence = execute_task(:generate_next_sentence,
                                inputs: { existing_content: story_data[:content] })
    result = execute_task(:append_to_story,
                         inputs: { sentence: new_sentence[:sentence] })
    { sentence: new_sentence[:sentence], total: result[:total_sentences] }
  end

  constraints do
    max_iterations 999999
    timeout "10m"
  end

  output do |outputs|
    puts "Added sentence: #{outputs[:sentence]}"
    puts "Story now has #{outputs[:total]} sentences"
  end
end
