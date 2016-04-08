class InboundTextMessagesController < ApplicationController
  skip_before_filter :verify_authenticity_token

  def create
    response = nil

    if session[:text_to_give].try(:[], :step) || params[:Body] =~ /give/i
      response = TwimlResponders::TextToGive.new(current_site, params, session).call
    elsif session[:knock_knock_joke].try(:[], :step) || params[:Body] =~ /knock knock/i
      response = TwimlResponders::KnockKnockJoke.new(params, session).call
    end

    return render xml: response.text if response
    render nothing: true
  end
end
