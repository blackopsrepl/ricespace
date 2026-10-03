# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# RiceSpace renders markup written by other people, so this policy is the second
# line behind the sanitiser (ProfileMarkup): even if something executable reached
# a page, there is no origin it could load a script from, nothing it could frame,
# and nowhere it could post a form. `style-src` allows inline styles because
# inline CSS is how profiles are decorated — the stylesheet parser, not this
# header, is what keeps those styles inside the profile's own column.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.connect_src     :self
    policy.font_src        :self, :data
    policy.form_action     :self
    # Video and stream links are embedded from the services that host them — this site
    # stores no video. `frame_src` is therefore the one hole in `default_src`, and it is
    # exactly three hosts wide: the three the embed builder can name. Nothing an author
    # pastes reaches this list, because an embed's host is chosen by `StreamEmbed` from a
    # literal rather than from the link.
    policy.frame_src       :self, *EmbedHosts::ALL
    policy.frame_ancestors :none
    policy.img_src         :self, :data, :https
    policy.object_src      :none
    policy.script_src      :self
    policy.style_src       :self, :unsafe_inline
  end

  # Everything this site ships is an inline script — the importmap and the module
  # entry point — and `script-src 'self'` blocks inline scripts outright. Without a
  # nonce generator the nonce is empty on both sides and the whole client side is
  # dead: Turbo never loads, so `data-turbo-confirm` never fires and the account
  # panel deletes on the click. The generator is what makes the tags the layout
  # emits runnable again.
  #
  # The nonce stays out of reach of a page's own markup: `ProfileMarkup` strips
  # `<script>` entirely, and the value is per-request.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
