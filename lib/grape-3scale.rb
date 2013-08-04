require 'kramdown'

module Grape
  class API
    class << self
      attr_reader :combined_routes

      def add_3scale_documentation(options={})
        documentation_class = create_documentation_class

        documentation_class.setup({:target_class => self}.merge(options))
        mount(documentation_class)

        @combined_routes = {}
        routes.each do |route|
          resource = route.route_path.match('\/(\w*?)[\.\/\(]').captures.first
          next if resource.empty?
          resource.downcase!
          @combined_routes[resource] ||= []
          @combined_routes[resource] << route
        end

      end

      private

      def create_documentation_class

        Class.new(Grape::API) do
          class << self
            def name
              @@class_name
            end
          end

          def self.setup(options)
            defaults = {
              :target_class => nil,
              :mount_path => '/3scale_doc',
              :base_path => nil,
              :api_version => '0.1',
              :markdown => false,
              :hide_documentation_path => false,
              :hide_format => false
            }
            options = defaults.merge(options)

            @@target_class = options[:target_class]
            @@mount_path = options[:mount_path]
            @@class_name = options[:class_name] || options[:mount_path].gsub('/','')
            @@markdown = options[:markdown]
            @@hide_documentation_path = options[:hide_documentation_path]
            @@hide_format = options[:hide_format]
            api_version = options[:api_version]
            base_path = options[:base_path]
            @@default_params = options[:default_params]



            desc '3scale compatible API description'
            get @@mount_path do
              header['Access-Control-Allow-Origin'] = '*'
              header['Access-Control-Request-Method'] = '*'
              routes = @@target_class::combined_routes

              if @@hide_documentation_path
                routes.reject!{ |route, value| "/#{route}/".index(parse_path(@@mount_path, nil) << '/') == 0 }
              end

              routes_array = routes.keys.inject([]) do |array, name|

                routes[name].each do |route|
                  notes = if route.route_notes && @@markdown
                    Kramdown::Document.new(strip_heredoc(route.route_notes)).to_html
                  else
                    route.route_notes
                  end
                  http_codes = parse_http_codes route.route_http_codes

                  operations = {
                      :notes => notes,
                      :group => name,
                      :summary => route.route_description || '',
                      :nickname   => route.route_method + route.route_path.gsub(/[\/:\(\)\.]/,'-'),
                      :httpMethod => route.route_method,
                      :parameters => parse_header_params(route.route_headers, @@default_params) +
                        parse_params(route.route_params, route.route_path, route.route_method, @@default_params)
                  }
                  operations.merge!({:errorResponses => http_codes}) unless http_codes.empty?
                  array << {
                    :path => parse_path(route.route_path, api_version),
                    :operations => [operations]
                  }
                end
                array
              end
              {
                apiVersion: api_version,
                swaggerVersion: "1.1",
                basePath: parse_base_path(base_path, request),
                operations:[],
                apis: routes_array
              }
            end

            desc '3scale compatible API description for specific API', :params =>
              {
                "name" => { :desc => "Resource name of mounted API", :type => "string", :required => true },
              }
            get "#{@@mount_path}/:name" do
              header['Access-Control-Allow-Origin'] = '*'
              header['Access-Control-Request-Method'] = '*'
              routes = @@target_class::combined_routes[params[:name]]
              routes_array = routes.map do |route|
                notes = route.route_notes && @@markdown ? Kramdown::Document.new(strip_heredoc(route.route_notes)).to_html : route.route_notes
                http_codes = parse_http_codes route.route_http_codes
                operations = {
                    :notes => notes,
                    :summary => route.route_description || '',
                    :nickname   => route.route_method + route.route_path.gsub(/[\/:\(\)\.]/,'-'),
                    :httpMethod => route.route_method,
                    :parameters => parse_header_params(route.route_headers, @@default_params) +
                      parse_params(route.route_params, route.route_path, route.route_method, @@default_params)
                }
                operations.merge!({:errorResponses => http_codes}) unless http_codes.empty?
                {
                  :path => parse_path(route.route_path, api_version),
                  :operations => [operations]
                }
              end

              {
                apiVersion: api_version,
                swaggerVersion: "1.1",
                basePath: parse_base_path(base_path, request),
                resourcePath: "",
                apis: routes_array
              }
            end

          end


          helpers do
            def parse_params(params, path, method, default_params)
              if params
                params.map do |param, value|
                  defs = {}
                  if default_params && default_params[param]
                    defs = default_params[param]
                  end
                  defs[:description] ||= ""
                  defs[:type] ||= "String"
                  defs[:paramType] ||= "query"
                  defs[:full_name] ||= param
                  defs[:threescale_name] ||= ""
                  defs[:required] ||= false

                  value[:type] = 'file' if value.is_a?(Hash) && value[:type] == 'Rack::Multipart::UploadedFile'

                  dataType = (value.is_a?(Hash) && value.has_key?(:type)) ? value[:type]||'String' : defs[:type]
                  description =  (value.is_a?(Hash) && (value.has_key?(:desc) || value.has_key?(:description))) ? value[:desc] || value[:description] : defs[:description]
                  required =  (value.is_a?(Hash)  && value.has_key?(:required)) ? !!value[:required] : defs[:required]
                  paramType = path.include?(":#{param}") ? 'path' : defs[:paramType]
                  name = (value.is_a?(Hash) && value[:full_name]) || defs[:full_name]
                  threescale_name =  (value.is_a?(Hash) && value.has_key?(:threescale_name)) ? value[:threescale_name] : defs[:threescale_name]
                  defaultValue = (value.is_a?(Hash) && value.has_key?(:default)) ? value[:default] : defs[:default]
                  allowedValues = (value.is_a?(Hash) && value.has_key?(:allowedValues)) ? value[:allowedValues] : defs[:allowedValues]
                  
                  retvals = {
                    paramType: paramType,
                    name: name,
                    description: description,
                    dataType: dataType,
                    required: required,
                  }
                  retvals[:threescale_name] = threescale_name if threescale_name.to_s.length > 0
                  retvals[:defaultValue] = defaultValue if defaultValue
                  retvals[:allowedValues] = allowedValues if allowedValues
                  retvals
                end
              else
                []
              end
            end


            def parse_header_params(params, default_params)
              if params
                params.map do |param, value|

                  if default_params && default_params[param]
                    defs = default_params[param]
                  end
                  defs[:description] ||= ""
                  defs[:type] ||= "String"
                  defs[:full_name] ||= param
                  defs[:threescale_name] ||= ""
                  defs[:required] ||= false

                  dataType =  defs[:type]
                  description = (value.is_a?(Hash) && value.has_key?(:description)) ? value[:description] : defs[:description]
                  required = (value.is_a?(Hash)  && value.has_key?(:required)) ? !!value[:required] : defs[:required]
                  threescale_name = (value.is_a?(Hash) && value.has_key?(:threescale_name))  ? value[:threescale_name] : defs[:threescale_name]
                  name =  defs[:full_name]
                  defaultValue =  defs[:default]
                  allowedValues =  defs[:allowedValues]
                  paramType = "header"

                  retvals = {
                    paramType: paramType,
                    name: name,
                    description: description,
                    dataType: dataType,
                    required: required,
                  }
                  retvals[:threescale_name] = threescale_name if threescale_name.to_s.length > 0
                  retvals[:defaultValue] = defaultValue if defaultValue
                  retvals[:allowedValues] = allowedValues if allowedValues
                  retvals
                end
              else
                []
              end
            end

            def parse_path(path, version)
              # adapt format to swagger format
              parsed_path = path.gsub '(.:format)', ( @@hide_format ? '' : '.{format}')
              # This is attempting to emulate the behavior of
              # Rack::Mount::Strexp. We cannot use Strexp directly because
              # all it does is generate regular expressions for parsing URLs.
              # TODO: Implement a Racc tokenizer to properly generate the
              # parsed path.
              parsed_path = parsed_path.gsub(/:([a-zA-Z_]\w*)/, '{\1}')
              # add the version
              version ? parsed_path.gsub('{version}', version) : parsed_path
            end

            def parse_http_codes codes
              codes ||= {}
              codes.collect do |k, v|
                { code: k, reason: v }
              end
            end

            def try(*a, &b)
              if a.empty? && block_given?
                yield self
              else
                public_send(*a, &b) if respond_to?(a.first)
              end
            end

            def strip_heredoc(string)
              indent = string.scan(/^[ \t]*(?=\S)/).min.try(:size) || 0
              string.gsub(/^[ \t]{#{indent}}/, '')
            end

            def parse_base_path(base_path, request)
              (base_path.is_a?(Proc) ? base_path.call(request) : base_path) || request.base_url
            end
          end
        end
      end
    end
  end
end
