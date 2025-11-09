# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LanguageOperator::Dsl::WebhookDefinition do
  let(:webhook) { described_class.new('/test/webhook') }

  describe '#initialize' do
    it 'sets the path' do
      expect(webhook.path).to eq('/test/webhook')
    end

    it 'defaults to POST method' do
      expect(webhook.http_method).to eq(:post)
    end

    it 'has no handler by default' do
      expect(webhook.handler).to be_nil
    end
  end

  describe '#method' do
    it 'sets the HTTP method' do
      webhook.method(:get)
      expect(webhook.http_method).to eq(:get)
    end

    it 'accepts different HTTP verbs' do
      %i[get post put delete patch].each do |verb|
        webhook.method(verb)
        expect(webhook.http_method).to eq(verb)
      end
    end
  end

  describe '#on_request' do
    it 'sets the request handler' do
      handler = proc { |_context| { ok: true } }
      webhook.on_request(&handler)

      expect(webhook.handler).to eq(handler)
    end

    it 'receives context in the handler' do
      received_context = nil
      webhook.on_request do |context|
        received_context = context
      end

      webhook.handler.call({ test: 'data' })
      expect(received_context).to eq({ test: 'data' })
    end
  end

  describe '#register' do
    let(:web_server) { instance_double(LanguageOperator::Agent::WebServer) }

    it 'registers the webhook with a web server' do
      webhook.on_request { |_context| { ok: true } }

      expect(web_server).to receive(:register_route).with(
        '/test/webhook',
        method: :post,
        authentication: nil,
        validations: []
      )

      webhook.register(web_server)
    end

    it 'does not register if no handler is defined' do
      expect(web_server).not_to receive(:register_route)
      webhook.register(web_server)
    end

    it 'passes the correct HTTP method' do
      webhook.method(:get)
      webhook.on_request { |_context| { ok: true } }

      expect(web_server).to receive(:register_route).with(
        '/test/webhook',
        method: :get,
        authentication: nil,
        validations: []
      )

      webhook.register(web_server)
    end
  end

  describe 'DSL usage' do
    it 'can be configured using instance_eval' do
      webhook_def = described_class.new('/github/pr')

      webhook_def.instance_eval do
        method :post
        on_request do |context|
          { pr_number: context[:params]['number'] }
        end
      end

      expect(webhook_def.http_method).to eq(:post)
      expect(webhook_def.handler).to be_a(Proc)
    end
  end
end
