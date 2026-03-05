class LeadsController < ApplicationController
  before_action :require_login
  before_action :set_lead, only: [:show, :edit, :update, :destroy]

  def index
    @leads = Lead.order(created_at: :desc).page(params[:page]).per(20)
  end

  def show
  end

  def new
    @lead = Lead.new
  end

  def create
    @lead = Lead.new(lead_params)
    if @lead.save
      redirect_to @lead, notice: "Lead created."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @lead.update(lead_params)
      redirect_to @lead, notice: "Lead updated."
    else
      render :edit
    end
  end

  def destroy
    @lead.destroy
    redirect_to leads_path, notice: "Lead deleted."
  end

  private

  def set_lead
    @lead = Lead.find(params[:id])
  end

  def lead_params
    params.require(:lead).permit(:first_name, :last_name, :email, :company, :phone, :status, :source, :notes)
  end
end
