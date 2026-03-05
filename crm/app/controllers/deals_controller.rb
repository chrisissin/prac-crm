class DealsController < ApplicationController
  before_action :require_login
  before_action :set_deal, only: [:show, :edit, :update, :destroy]

  def index
    @deals = Deal.includes(:account, :contact).order(created_at: :desc).page(params[:page]).per(20)
  end

  def show
  end

  def new
    @deal = Deal.new
  end

  def create
    @deal = Deal.new(deal_params)
    if @deal.save
      redirect_to @deal, notice: "Deal created."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @deal.update(deal_params)
      redirect_to @deal, notice: "Deal updated."
    else
      render :edit
    end
  end

  def destroy
    @deal.destroy
    redirect_to deals_path, notice: "Deal deleted."
  end

  private

  def set_deal
    @deal = Deal.find(params[:id])
  end

  def deal_params
    params.require(:deal).permit(:name, :value, :stage, :expected_close_date, :notes, :account_id, :contact_id)
  end
end
