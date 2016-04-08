class TwimlResponders::TextToGive
  include Rails.application.routes.url_helpers # for new_donation_url
  include ActionView::Helpers::NumberHelper # for number_to_currency
  include UrlsHelper # for shorten_url and secure_url_options

  attr_reader :params, :current_site

  def initialize(current_site, params, session)
    @current_site = current_site
    @params = params

    session[:text_to_give] ||= {}
    session[:text_to_give][:step] ||= 0
    @session = session
  end

  def call
    Twilio::TwiML::Response.new do |r|
      # Most of the time, we're only responding with one message, but sometimes
      # multiple are sent back (transaction failure in step 2 for instance).
      # [].flatten ensures we always have a non-nested array.
      messages = [send("step_#{step}_response")].flatten
      messages.each do |message|
        r.Message message
      end
    end
  end

  private

  def step_0_response
    message = "How much would you like to donate to #{current_site.name} (50, 100, etc)?"
    message = "Hi, #{user.first_name}. #{message}" if user
    increment_step
    message
  end

  def step_1_response
    self.amount = body.gsub('$', '').gsub(',', '').to_f

    if amount > 0
      if existing_donor?
        message = "Reply YES to confirm your #{number_to_currency(amount)} donation to #{current_site.name}"
        message << " using your #{last_donation.payment_account_mask.downcase}" if last_donation.payment_account_mask
        increment_step
      else
        message = "Awesome! Just follow this link to finish your donation and then all future donations can be completed by text! #{donation_url}"
        cleanup_session
      end
    else
      message = "Please enter a valid donation amount."
    end

    message
  end

  def step_2_response
    if body =~ /yes/i && existing_donor?
      response = process_payment
      if response.success?
        add_donation(response)
        message = "Thanks, #{user.first_name}! Your donation was received."
      else
        message = ["Error: #{response.message}"]
        message << "I'm sorry.  We weren't able to complete your donation over text messaging."
        message << "Here's a url that you can use to donate using your phone's web browser #{donation_url}"
      end

      cleanup_session
      message
    else

    end
  end

  def body
    params[:Body]
  end

  def phone_number
    @phone_number ||= params[:From].gsub('+1', '')
  end

  def user
    @user ||= current_site.users.where(phone: phone_number).first
  end

  def step
    @session[:text_to_give][:step]
  end

  def increment_step
    @session[:text_to_give][:step] += 1
  end

  def amount
    @session[:text_to_give][:amount]
  end

  def amount=(value)
    @session[:text_to_give][:amount] = value
  end

  def cleanup_session
    @session.delete(:text_to_give)
  end

  # Determines if the user (looked up by phone number) has donated previously
  # and if a token is available to charge them again.
  def existing_donor?
    if user && last_donation
      (
        (current_site.payment_gateway == 'stripe' && user.stripe_customer_id.present?) ||
        (current_site.payment_gateway == 'blue_pay' && last_donation.transaction_id.present?)
      )
    else
      false
    end
  end

  def last_donation
    user.try(:last_donation)
  end

  def donation_url
    # The shorten_url method lives in UrlsHelper and uses Bitly's service to provide
    # a shortened url.  Every character counts in SMS.
    shorten_url(new_donation_url(secure_url_options.merge(
      'donation[source]' => 'text_to_give',
      'donation[amount]' => amount,
      'donation[user_attributes][phone]' => phone_number
    )))
  end

  def process_payment
    # activemerchant requires amount to be passed as cents
    amount_in_cents = (amount * 100).to_i
    options = {}
    payment_object = nil

    # Both Stipe and BluePay allow processing using a token from a previous
    # success response.
    if current_site.payment_gateway == 'stripe'
      options[:customer] = user.stripe_customer_id
    elsif current_site.payment_gateway == 'blue_pay'
      payment_object = last_donation.transaction_id
    end

    # Process payment using activemerchant
    current_site.gateway.purchase(amount_in_cents, payment_object, options)
  end

  def add_donation(response)
    # Adds a donation record to the db
    donation = user.donations.new
    donation.amount = amount
    donation.payment_method = last_donation.payment_method
    donation.parse_active_merchant_response(response)
    donation.skip_transaction = true # Skip since we've already processed the payment
    donation.save

    # Fires off confirmation email to admin notifying him/her of donation
    DonationMailer.confirmation(donation.id).deliver_later

    # Adds entry to site & user's activity feed
    donation.create_activity 'create', {
      site: current_site,
      owner: user,
      parameters: { owner_name: user.name }
    }
  end
end
