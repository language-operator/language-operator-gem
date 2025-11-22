require 'language_operator'

agent "s003" do
  description "Build a story one sentence at a time, with one new sentence every hour"
  mode :scheduled
  schedule "0 * * * *"

  task :read_existing_story,
     inputs: {  },
     outputs: { content: 'string', sentence_count: 'integer' } do |inputs|
  file_info = execute_tool('get_file_info', { path: 'story.txt' })
  if file_info.is_a?(Hash) && file_info[:error]
    { content: '', sentence_count: 0 }
  else
    content = execute_tool('read_file', { path: 'story.txt' })
    sentence_count = content.split(/[.!?]+\s*/).length
    { content: content, sentence_count: sentence_count }
  end
end

  task :generate_next_sentence,
    instructions: "Generate exactly one new sentence to continue this story. Maintain consistent tone and style. Only output the new sentence.",
    inputs: { existing_content: 'string' },
    outputs: { sentence: 'string' }

  task :append_to_story,
     inputs: { sentence: 'string' },
     outputs: { success: 'boolean', total_sentences: 'integer' } do |inputs|
  existing_content = execute_tool('read_file', { path: 'story.txt' })
  
  # Determine if we need to add a newline before appending
  content_to_write = if existing_content.empty?
                       inputs[:sentence]
                     else
                       "\n#{inputs[:sentence]}"
                     end
  
  # Append the new sentence to the file
  execute_tool('write_file', { path: 'story.txt', content: existing_content + content_to_write })
  
  # Count total sentences by splitting on newlines and filtering empty lines
  sentences = existing_content.split("\n").reject(&:empty?)
  new_sentence_count = sentences.length + 1
  
  { success: true, total_sentences: new_sentence_count }
end

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
