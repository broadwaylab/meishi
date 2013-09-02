# This is a base CardDAV resource class.  It defines some standard
# DAV / CardDAV properties as well as some helper functions used by
# the other resource classes.
class Carddav::BaseResource < DAV4Rack::Resource
  # On the subclass define a similar hash for properties specific to that
  # subclass, and another hash for properties specific to that subclass that
  # should not be returned in an allprop request.
  # Properties defined here may be implemented in the subclass, but do not
  # need to be defined there
  BASE_PROPERTIES = {
    'DAV:' => %w(
      creationdate
      current-user-principal
      displayname
      getcontentlength
      getcontenttype
      getetag
      getlastmodified
      principal-URL
      resourcetype
    ),

    # Define the carddav namespace as an empty array so it will fall through
    # to dav4rack and carddav properties will return a NotImplemented instead
    # of BadRequest
    'urn:ietf:params:xml:ns:carddav' => []
  }

  # Properties that should be implemented by every resource but that should
  # not be included in an allprop request.  See also: RFC 3744 §4 and §5
  BASE_EXPLICIT_PROPERTIES = {
    'DAV:' => %w(
      acl
      acl-restrictions
      current-user-privilege-set
      group
      inherited-acl-set
      owner
      principal-collection-set
      supported-privilege-set
    )
  }

  # List of supported privileges and their English descriptions.
  PRIVILEGES = {
    :read                               => 'Read any object',
    :'read-acl'                         => 'Read ACL',
    :'read-current-user-privilege-set'  => 'Read current user privilege set property',
    :'write-content'                    => 'Write resource content',
    :unlock                             => 'Unlock resource'
  }

    # This is a convenience function for CalDAV properties.  It will define
    # a function named after the first argument (a symbol) that populates three
    # instance variables: @attributes, @children, and @attribute.
    # @note The keyword next MUST be used inside of blocks instead of return.
    # @param method [Symbol]
    # @param options [Hash]
    # @param block [Proc]
    # @return [void]
  def self.prop(method, options={}, &block)
    self.class_eval do
      define_method(method) do |attributes={}, children=Nokogiri::XML::NodeSet.new(Nokogiri::XML(''))|
        self.instance_variable_set(:@attributes, attributes)
        self.instance_variable_set(:@children, children)
        self.instance_variable_set(:@attribute, method)

        unless options[:args] == true or method =~ /=$/
          unexpected_arguments(attributes, children)
        end

        unless options[:noargs] == true or not method =~ /=$/
          expected_arguments(attributes, children)
        end

        self.instance_exec(&block)
      end

      # DAV4Rack will clobber public methods, so let's make sure these are all protected.
      protected method
    end
  end

    # Performs some initial configuration. This function is called from the
    # DAV4Rack initializer and does some mangling to make OSX Snow Leopard's
    # AddressBook.app happy.  Frist, it instructs DAV4Rack to send paths in
    # lieu of proper URLs in PROPFIND responses.  Second, it adds two of 
    # Apple's proprietary XML namespaces to all XML responses.
  def setup
    # TODO: Rework this to be a function so that non OSX clients get URLs
    # and OSX.6 gets paths via the CURRENT_PRINCIPAL_NO_URL quirk.
    @propstat_relative_path = true
    @root_xml_attributes = {
      'xmlns:C' => 'urn:ietf:params:xml:ns:carddav', 
      'xmlns:APPLE1' => 'http://calendarserver.org/ns/'
    }
    @debug_props = ENV['MEISHI_DEBUG_SUPPORTED_PROPS'].to_i
  end

  # Returns the warden authentication object
  def warden
    request.env['warden']
  end

    # Returns the current user object. If not logged in, the user is
    # prompted for authentication credentials.
  def current_user
    @current_user ||= warden.authenticate(:scope => :user)
    @current_user
  end

  def is_self?(other_path)
    ary = [@public_path]
    ary.push(@public_path+'/') if @public_path[-1] != '/'
    ary.push(@public_path[0..-2]) if @public_path[-1] == '/'
    ary.include? other_path
  end

  def get_property(element)
    name = element[:name]
    namespace = element[:ns_href]

    our_properties = gather_properties

    unless our_properties.include? namespace
      raise BadRequest
    end

    fn = name.underscore

    if our_properties[namespace].include?(name)
      # The base dav4rack handler will use nicer looking function names for some properties
      # Let's just humor it.  If we don't define a local prop_foo method, fall back to the
      # super class's implementation of get_property which we hope will handle our request.
      if self.respond_to?(fn)
        if element[:children].empty? and element[:attributes].empty?
          return self.send(fn.to_sym)
        else
          return self.send(fn.to_sym, element[:attributes], element[:children])
        end
      end
    end

    if @debug_props >= 1
      Rails.logger.debug "Skipping ns:\"#{namespace}\" prop:#{name} sym:#{fn.inspect} on #{self.class} respond: #{self.respond_to?(fn)} our_props: #{our_properties[namespace].include?(name)}"
      if @debug_props >= 2
        Rails.logger.debug "Our properties: #{our_properties[namespace].join(', ')}"
        Rails.logger.debug ""
      end
    end

    super(element)
  end

  def set_property(element, value)
    Rails.logger.debug "set_property(#{element.inspect}, #{value.inspect})" if ENV['MEISHI_DEBUG_PROPPATCH'].to_i >= 1

    name = element[:name]
    namespace = element[:ns_href]

    our_properties = gather_properties

    unless our_properties.include? namespace
      raise BadRequest
    end

    fn = "#{name.underscore}="

    if our_properties[namespace].include?(name)
      # The base dav4rack handler will use nicer looking function names for some properties
      # Let's just humor it.  If we don't define a local prop_foo method, fall back to the
      # super class's implementation of get_property which we hope will handle our request.
      if self.respond_to?(fn)
        return self.send(fn.to_sym, element[:attributes], value)
      end
    end

    if @debug_props >= 1
      Rails.logger.debug "Skipping ns:\"#{namespace}\" prop:#{name} sym:#{fn.inspect} on #{self.class} respond: #{self.respond_to?(fn)} our_props: #{our_properties[namespace].include?(name)}"
      if @debug_props >= 2
        Rails.logger.debug "Our properties: #{our_properties[namespace].join(', ')}"
        Rails.logger.debug ""
      end
    end

    super(element)
  end

  # Some properties shouldn't be included in an allprop request
  # but it's nice to do some sanity checking so keeping a list is good
  def properties
    gather_properties(false).inject([]) do |ret, (namespace, proplist)|
      proplist.each do |prop|
        ret << {name: prop, ns_href: namespace, children: [], attributes: []}
      end
      ret
    end
  end

  # Properties in alphabetical order
  # Properties need to be protected so that dav4rack doesn't alias them away
  protected

  # RFC 3744 §5.5
  # Let's implement the simplest policy possible... modifying the permissions
  # via WebDAV is not supported (yet?).
  # TODO: Articulate permissions here for all users as part of a proper admin implementation
  # TODO: Offer up unique principal URIs on a per-user basis
  prop :acl do
    s="
    <D:acl xmlns:D='DAV:'>
      <D:ace>
        <D:principal>
          <D:href>#{url_or_path(:principal)}</D:href>
        </D:principal>
        <D:protected/>
        <D:grant>
        %s
        </D:grant>
      </D:ace>
    </D:acl>"
    s %= get_privileges_aggregate
    Nokogiri::XML::DocumentFragment.parse(s)      
  end

  # RFC 3744 §5.6
  prop :acl_restrictions do
    s="<D:acl-restrictions xmlns:D='DAV:'><D:grant-only/><D:no-invert/></D:acl-restrictions>"
    Nokogiri::XML::DocumentFragment.parse(s)
  end

  # This violates the spec that requires an HTTP or HTTPS URL.  Unfortunately,
  # Apple's AddressBook.app treats everything as a pathname.  Also, the model
  # shouldn't need to know about the URL scheme and such.
  prop :current_user_principal do
    s="<D:current-user-principal xmlns:D='DAV:'><D:href>#{url_or_path(:principal)}</D:href></D:current-user-principal>"
    Nokogiri::XML::DocumentFragment.parse(s)
  end

  # RFC 3744 §5.4
  prop :current_user_privilege_set do
    s='<D:current-user-privilege-set xmlns:D="DAV:">%s</D:current-user-privilege-set>'

    s %= get_privileges_aggregate
    Nokogiri::XML::DocumentFragment.parse(s)
  end

  # RFC 3744 §5.2
  # Servers MAY implement DAV:group as protected property and MAY return
  # an empty DAV:group element as property value in case no group
  # information is available.
  prop :group do
  end

  # RFC 3744 §5.7
  # <!ELEMENT inherited-acl-set (href*)>
  prop :inherited_acl_set do
  end

  # RFC 3744 §5.1
  # <!ELEMENT owner (href?)>
  prop :owner do
    s="<D:owner xmlns:D='DAV:'><D:href>#{url_or_path(:principal)}</D:href></D:owner>"
    Nokogiri::XML::DocumentFragment.parse(s)
  end

  # RFC 3744 §5.1.2
  prop :owner= do
    raise Forbidden
  end

  # RFC 3744 §5.8
  prop :principal_collection_set do
    s="<D:principal-collection-set xmlns:D='DAV:'><D:href>#{url_or_path(:principal)}</D:href></D:principal-collection-set>"
    Nokogiri::XML::DocumentFragment.parse(s)
  end

  prop :principal_url do
    s="<D:principal-URL xmlns:D='DAV:'><D:href>#{url_or_path(:principal)}</D:href></D:principal-URL>"
    Nokogiri::XML::DocumentFragment.parse(s)
  end

  # RFC 3744 §5.3
  prop :supported_privilege_set do
    xml_snippet('supported-privilege-set') do |xml|
      PRIVILEGES.each do |privilege, description|
        xml.send :'supported-privilege' do
          xml.privilege do
            xml.send privilege
            xml.description(description, {lang: :en})
          end
        end
      end
    end
  end

  # These are not properties.

  protected
  def children
    []
  end

  def gather_properties(include_explicit=true)
    begin
      our_properties = Carddav::BaseResource.merge_properties(BASE_PROPERTIES, BASE_EXPLICIT_PROPERTIES)
      our_properties = Carddav::BaseResource.merge_properties(our_properties, self.class::ALL_PROPERTIES)
      our_properties = Carddav::BaseResource.merge_properties(our_properties, self.class::EXPLICIT_PROPERTIES) if include_explicit
    rescue => e
      if @debug_props >= 2
        Rails.logger.info "Failed to parse supported properties #{e.inspect}"
      end

      # Just in case we don't have any properties defined on the subclass
      if include_explicit
        our_properties = Carddav::BaseResource.merge_properties(BASE_PROPERTIES, BASE_EXPLICIT_PROPERTIES)
      else
        our_properties = BASE_PROPERTIES.dup
      end
    end
    our_properties
  end

  def self.merge_properties(all, explicit)
    ret = all.dup
    explicit.each do |key, value|
      ret[key] ||= []
      ret[key] += value
      ret[key].uniq!
    end
    ret
  end

  def xml_snippet(root_type)
    raise ArgumentError.new 'Expecting block' unless block_given?

    builder = Nokogiri::XML::Builder.new do |xml_base|
      xml_base.send(root_type.to_s, {'xmlns:D' => 'DAV:'}.merge(root_xml_attributes)) do
        xml_base.parent.namespace = xml_base.parent.namespace_definitions.first
        xml = xml_base['D']
        yield xml
      end
    end
    builder.doc.root
  end

  # Call this so that we log requests with unexepcted extra fluff
  def unexpected_arguments(attributes, children)
    return if (attributes.nil? or attributes.empty?) and (children.nil? or children.empty?)

    Rails.logger.error "#{@attribute} request did not expect arguments: #{attributes.inspect} / #{children.inspect}"
  end

  # Call this so that we can log requests where we expect children and
  # don't get them.
  def expected_arguments(attributes, children)
    return unless (attributes.nil? or attributes.empty?) and (children.nil? or children.empty?)

    Rails.logger.error "#{@attribute} request expected arguments: #{attributes.inspect} / #{children.inspect}"
  end


  # Default URL builder options -- we need these because we're doing bad things by calling
  # the URL helpers from outside the view context.
  def url_options
    {host: request.host, port: request.port, protocol: request.scheme}
  end

  # So, for our first quirk: MacOS 10.6 needs paths and not URLs (it will treat URLs as paths...)
  def url_or_path(route_name, fluff={})
    method = nil

    use_path = Quirks.match(:CURRENT_PRINCIPAL_NO_URL, request.user_agent)
    method = (route_name.to_s + (use_path ? '_path' : '_url')).to_sym
    options = []
    options << fluff.delete(:object) if fluff.include? :object
    options << url_options.merge(fluff)
    URLHelpers.send(method, *options)
  end

  private
  def get_privileges_aggregate(privilege_element='D:privilege')
    privileges_aggregate = PRIVILEGES.inject('') do |ret, (priv, desc)|
      ret << "<#{privilege_element}><#{priv} /></#{privilege_element}>" % priv
    end
  end

end
