# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'language_operator/dsl/http'

RSpec.describe LanguageOperator::Dsl::HTTP do
  before do
    WebMock.disable_net_connect!
  end

  describe '.get' do
    context 'with valid HTTP/HTTPS URLs' do
      it 'allows HTTPS requests' do
        stub_request(:get, 'https://example.com/api')
          .to_return(status: 200, body: '{"success": true}', headers: { 'Content-Type' => 'application/json' })

        result = described_class.get('https://example.com/api')

        expect(result[:success]).to be(true)
        expect(result[:status]).to eq(200)
        expect(result[:json]).to eq({ 'success' => true })
      end

      it 'allows HTTP requests' do
        stub_request(:get, 'http://example.com/api')
          .to_return(status: 200, body: 'OK')

        result = described_class.get('http://example.com/api')

        expect(result[:success]).to be(true)
        expect(result[:status]).to eq(200)
        expect(result[:body]).to eq('OK')
      end

      it 'allows requests with ports' do
        stub_request(:get, 'https://example.com:8080/api')
          .to_return(status: 200, body: 'OK')

        result = described_class.get('https://example.com:8080/api')

        expect(result[:success]).to be(true)
      end
    end

    context 'with invalid schemes' do
      it 'blocks file:// schemes' do
        result = described_class.get('file:///etc/passwd')

        expect(result[:error]).to include("URL scheme 'file' not allowed")
        expect(result[:success]).to be(false)
      end

      it 'blocks ftp:// schemes' do
        result = described_class.get('ftp://internal.server.com/file.txt')

        expect(result[:error]).to include("URL scheme 'ftp' not allowed")
        expect(result[:success]).to be(false)
      end

      it 'blocks gopher:// schemes' do
        result = described_class.get('gopher://example.com/')

        expect(result[:error]).to include("URL scheme 'gopher' not allowed")
        expect(result[:success]).to be(false)
      end

      it 'handles uppercase schemes' do
        result = described_class.get('FILE:///etc/passwd')

        expect(result[:error]).to include("URL scheme 'file' not allowed")
        expect(result[:success]).to be(false)
      end

      it 'blocks URLs without schemes' do
        result = described_class.get('example.com')

        expect(result[:error]).to include("URL scheme '' not allowed")
        expect(result[:success]).to be(false)
      end
    end

    context 'with blocked IP addresses' do
      it 'blocks private IP range 10.0.0.0/8' do
        result = described_class.get('http://10.1.1.1/api')

        expect(result[:error]).to include('private IP range (RFC 1918)')
        expect(result[:success]).to be(false)
      end

      it 'blocks private IP range 172.16.0.0/12' do
        result = described_class.get('http://172.16.0.1/api')

        expect(result[:error]).to include('private IP range (RFC 1918)')
        expect(result[:success]).to be(false)
      end

      it 'blocks private IP range 192.168.0.0/16' do
        result = described_class.get('http://192.168.1.1/api')

        expect(result[:error]).to include('private IP range (RFC 1918)')
        expect(result[:success]).to be(false)
      end

      it 'blocks localhost IP 127.0.0.1' do
        result = described_class.get('http://127.0.0.1:8080/api')

        expect(result[:error]).to include('loopback address')
        expect(result[:success]).to be(false)
      end

      it 'blocks link-local address (AWS metadata endpoint)' do
        result = described_class.get('http://169.254.169.254/latest/meta-data/')

        expect(result[:error]).to include('link-local address (AWS metadata endpoint)')
        expect(result[:success]).to be(false)
      end

      it 'blocks broadcast address' do
        result = described_class.get('http://255.255.255.255/')

        expect(result[:error]).to include('broadcast address')
        expect(result[:success]).to be(false)
      end

      it 'blocks IPv6 loopback' do
        result = described_class.get('http://[::1]:8080/api')

        expect(result[:error]).to include('IPv6 loopback address')
        expect(result[:success]).to be(false)
      end
    end

    context 'with hostname resolution' do
      before do
        # Mock hostname resolution for testing
        allow(Addrinfo).to receive(:getaddrinfo).with('blocked-host.com', nil, nil, :STREAM)
                                                .and_return([
                                                              double(ip_address: '127.0.0.1')
                                                            ])

        allow(Addrinfo).to receive(:getaddrinfo).with('safe-host.com', nil, nil, :STREAM)
                                                .and_return([
                                                              double(ip_address: '8.8.8.8')
                                                            ])

        allow(Addrinfo).to receive(:getaddrinfo).with('unresolvable.invalid', nil, nil, :STREAM)
                                                .and_raise(SocketError, 'Name or service not known')
      end

      it 'blocks hostnames that resolve to blocked IPs' do
        result = described_class.get('http://blocked-host.com/api')

        expect(result[:error]).to include("Host 'blocked-host.com' resolves to blocked IP address")
        expect(result[:error]).to include('loopback address')
        expect(result[:success]).to be(false)
      end

      it 'allows hostnames that resolve to safe IPs' do
        stub_request(:get, 'http://safe-host.com/api')
          .to_return(status: 200, body: 'OK')

        result = described_class.get('http://safe-host.com/api')

        expect(result[:success]).to be(true)
      end

      it 'handles unresolvable hostnames gracefully' do
        result = described_class.get('http://unresolvable.invalid/api')

        expect(result[:error]).to include('Unable to resolve hostname: unresolvable.invalid')
        expect(result[:success]).to be(false)
      end
    end

    context 'with malformed URLs' do
      it 'handles invalid URL format' do
        result = described_class.get('not-a-url')

        expect(result[:error]).to include('URL scheme')
        expect(result[:success]).to be(false)
      end

      it 'handles empty URLs' do
        result = described_class.get('')

        expect(result[:error]).to include('URL scheme')
        expect(result[:success]).to be(false)
      end

      it 'handles nil URLs' do
        result = described_class.get(nil)

        expect(result[:error]).to eq('URL cannot be nil')
        expect(result[:success]).to be(false)
      end
    end
  end

  describe '.post' do
    it 'applies same security validations' do
      result = described_class.post('file:///etc/passwd', json: { data: 'test' })

      expect(result[:error]).to include("URL scheme 'file' not allowed")
      expect(result[:success]).to be(false)
    end

    it 'blocks private IPs' do
      result = described_class.post('http://192.168.1.1/api', json: { data: 'test' })

      expect(result[:error]).to include('private IP range (RFC 1918)')
      expect(result[:success]).to be(false)
    end

    it 'allows valid HTTPS requests' do
      stub_request(:post, 'https://example.com/api')
        .with(body: '{"data":"test"}')
        .to_return(status: 201, body: '{"created": true}')

      result = described_class.post('https://example.com/api', json: { data: 'test' })

      expect(result[:success]).to be(true)
      expect(result[:status]).to eq(201)
    end
  end

  describe '.put' do
    it 'applies same security validations' do
      result = described_class.put('ftp://example.com/file', json: { data: 'test' })

      expect(result[:error]).to include("URL scheme 'ftp' not allowed")
      expect(result[:success]).to be(false)
    end
  end

  describe '.delete' do
    it 'applies same security validations' do
      result = described_class.delete('http://127.0.0.1:8080/api')

      expect(result[:error]).to include('loopback address')
      expect(result[:success]).to be(false)
    end
  end

  describe '.head' do
    it 'applies same security validations' do
      result = described_class.head('http://169.254.169.254/latest/meta-data/')

      expect(result[:error]).to include('link-local address (AWS metadata endpoint)')
      expect(result[:success]).to be(false)
    end
  end

  describe '.curl (deprecated)' do
    it 'raises security error' do
      expect { described_class.curl('http://example.com') }
        .to raise_error(LanguageOperator::SecurityError, /HTTP.curl has been removed for security reasons/)
    end
  end

  describe 'edge cases' do
    it 'handles URLs with unusual but valid public IPs' do
      # 8.8.8.8 is Google DNS, should be allowed
      stub_request(:get, 'http://8.8.8.8/api')
        .to_return(status: 200, body: 'OK')

      result = described_class.get('http://8.8.8.8/api')

      expect(result[:success]).to be(true)
    end

    it 'handles IPv6 addresses (non-loopback)' do
      # Stub the IPv6 request to avoid WebMock errors
      stub_request(:get, 'http://[2001:db8::1]/api')
        .to_return(status: 200, body: 'OK')

      result = described_class.get('http://[2001:db8::1]/api')

      # Should succeed since it's a public IPv6 address
      expect(result[:success]).to be(true)
    end
  end
end
