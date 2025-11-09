#!/usr/bin/env ruby
# frozen_string_literal: true

# GitHub Webhook Agent Example
#
# This example shows how to create an agent that receives GitHub webhook events
# with proper signature verification for security.
#
# Setup:
# 1. Set GITHUB_WEBHOOK_SECRET environment variable
# 2. Configure GitHub webhook to send events to https://<agent-url>/github/events
# 3. Select events you want to receive (e.g., pull_request, issues, push)
#
# GitHub webhook documentation:
# https://docs.github.com/en/webhooks

require 'bundler/setup'
require 'language_operator'

LanguageOperator::Dsl.define_agents do
  agent 'github-pr-reviewer' do
    description 'Automatically reviews pull requests and provides feedback'

    # Set to reactive mode to receive webhooks
    mode :reactive

    # GitHub Pull Request webhook
    webhook '/github/pull_request' do
      method :post

      # Verify GitHub webhook signature
      # GitHub sends signature in X-Hub-Signature-256 header
      # Format: "sha256=<signature>"
      authenticate do
        verify_signature(
          header: 'X-Hub-Signature-256',
          secret: ENV.fetch('GITHUB_WEBHOOK_SECRET', nil),
          algorithm: :sha256,
          prefix: 'sha256='
        )
      end

      # Validate request format
      require_content_type 'application/json'
      require_headers(
        'X-GitHub-Event' => nil, # Just check presence, any value OK
        'X-GitHub-Delivery' => nil
      )

      on_request do |context|
        event = JSON.parse(context[:body])
        action = event['action']
        pr = event['pull_request']

        case action
        when 'opened'
          handle_pr_opened(pr, context)
        when 'synchronize'
          handle_pr_updated(pr, context)
        when 'closed'
          handle_pr_closed(pr, context)
        else
          { status: 'ignored', action: action }
        end
      end
    end

    # GitHub Issue webhook
    webhook '/github/issues' do
      method :post

      authenticate do
        verify_signature(
          header: 'X-Hub-Signature-256',
          secret: ENV.fetch('GITHUB_WEBHOOK_SECRET', nil),
          algorithm: :sha256,
          prefix: 'sha256='
        )
      end

      require_content_type 'application/json'

      on_request do |context|
        event = JSON.parse(context[:body])
        action = event['action']
        issue = event['issue']

        case action
        when 'opened'
          {
            status: 'processed',
            message: "New issue: #{issue['title']}",
            issue_number: issue['number']
          }
        when 'labeled'
          {
            status: 'processed',
            message: "Issue labeled: #{event['label']['name']}"
          }
        else
          { status: 'ignored', action: action }
        end
      end
    end

    # GitHub Push webhook
    webhook '/github/push' do
      method :post

      authenticate do
        verify_signature(
          header: 'X-Hub-Signature-256',
          secret: ENV.fetch('GITHUB_WEBHOOK_SECRET', nil),
          algorithm: :sha256,
          prefix: 'sha256='
        )
      end

      require_content_type 'application/json'

      on_request do |context|
        event = JSON.parse(context[:body])
        ref = event['ref']
        commits = event['commits']

        {
          status: 'processed',
          message: "Received #{commits.length} commits on #{ref}",
          commits: commits.map { |c| c['message'] }
        }
      end
    end
  end
end

# Helper methods for PR handling
def handle_pr_opened(pr, _context)
  {
    status: 'processed',
    action: 'pr_opened',
    pr_number: pr['number'],
    pr_title: pr['title'],
    pr_url: pr['html_url'],
    message: "Reviewing PR ##{pr['number']}: #{pr['title']}"
  }
end

def handle_pr_updated(pr, _context)
  {
    status: 'processed',
    action: 'pr_updated',
    pr_number: pr['number'],
    message: "PR ##{pr['number']} was updated"
  }
end

def handle_pr_closed(pr, _context)
  {
    status: 'processed',
    action: 'pr_closed',
    pr_number: pr['number'],
    merged: pr['merged'],
    message: "PR ##{pr['number']} was #{pr['merged'] ? 'merged' : 'closed'}"
  }
end

# Run the agent if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  agent = LanguageOperator::Dsl.agent_registry.get('github-pr-reviewer')
  agent.run!
end
