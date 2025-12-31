# frozen_string_literal: true

module LanguageOperator
  module Utils
    # Utility for detecting organization context from cluster resources
    class OrgContext
      ORG_ID_LABEL = 'langop.io/organization-id'

      # Cache organization ID to avoid repeated API calls
      @cache = {}
      @cache_mutex = Mutex.new

      class << self
        # Get the current organization ID from cluster resources
        #
        # @param k8s_client [LanguageOperator::Kubernetes::Client] Kubernetes client
        # @return [String, nil] Organization ID or nil if not found
        def current_org_id(k8s_client)
          return nil unless k8s_client

          cache_key = "#{k8s_client.context}:#{k8s_client.current_namespace}"

          @cache_mutex.synchronize do
            # Return cached result if available and not expired
            cached = @cache[cache_key]
            return cached[:org_id] if cached && Time.now - cached[:timestamp] < cache_ttl

            # Detect org ID from cluster resources
            org_id = detect_org_id(k8s_client)

            # Cache the result
            @cache[cache_key] = {
              org_id: org_id,
              timestamp: Time.now
            }

            org_id
          end
        rescue StandardError => e
          # Log error but don't fail - return nil for legacy mode
          warn "Warning: Could not detect organization context: #{e.message}" if ENV['DEBUG']
          nil
        end

        # Clear the organization context cache
        def clear_cache!
          @cache_mutex.synchronize { @cache.clear }
        end

        # Get organization ID from a specific resource
        #
        # @param resource [Hash] Kubernetes resource manifest
        # @return [String, nil] Organization ID from labels
        def org_id_from_resource(resource)
          resource.dig('metadata', 'labels', ORG_ID_LABEL)
        end

        # Check if a resource has organization context
        #
        # @param resource [Hash] Kubernetes resource manifest
        # @return [Boolean] True if resource has org ID label
        def org_context?(resource)
          !org_id_from_resource(resource).nil?
        end

        private

        # Detect organization ID by examining cluster resources
        #
        # @param k8s_client [LanguageOperator::Kubernetes::Client] Kubernetes client
        # @return [String, nil] Organization ID or nil if not found
        def detect_org_id(k8s_client)
          # Try to find organization ID from any language operator resource
          # Check in order of likelihood: LanguageCluster, LanguageAgent, LanguageModel

          %w[LanguageCluster LanguageAgent LanguageModel LanguagePersona].each do |kind|
            resources = k8s_client.list_resources(kind)
            next if resources.empty?

            # Look for org ID in any resource of this type
            resources.each do |resource|
              org_id = org_id_from_resource(resource)
              return org_id if org_id
            end
          end

          nil
        rescue StandardError
          # If we can't query resources, assume legacy mode
          nil
        end

        # Cache TTL in seconds (5 minutes)
        def cache_ttl
          300
        end
      end
    end
  end
end
