class InboundTextMessagesController < ApplicationController
  skip_before_filter :verify_authenticity_token

  def create
    if session[:text_to_give].try(:[], :step) || params[:Body] =~ /give/i
      twiml_response = TextToGiveResponder.new(current_site, params, session).call
      return render xml: twiml_response.text
    end

    render nothing: true
  end
end
