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
    policy.frame_ancestors :none
    policy.img_src         :self, :data, :https
    policy.object_src      :none
    policy.script_src      :self
    policy.style_src       :self, :unsafe_inline
  end
end
