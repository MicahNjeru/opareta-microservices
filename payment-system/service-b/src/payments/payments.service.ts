import {
  Injectable,
  NotFoundException,
  Inject,
  LoggerService,
  ConflictException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Cache } from 'cache-manager';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { WINSTON_MODULE_NEST_PROVIDER } from 'nest-winston';
import { v4 as uuidv4 } from 'uuid';
import { Payment, PaymentStatus } from './entities/payment.entity';
import { CreatePaymentDto } from './dto/create-payment.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import { WebhookDto } from './dto/webhook.dto';
import { PaymentResponseDto, WebhookResponseDto } from './dto/payment-response.dto';
import { StateMachineService } from './services/state-machine.service';

@Injectable()
export class PaymentsService {
  constructor(
    @InjectRepository(Payment)
    private readonly paymentRepository: Repository<Payment>,
    private readonly stateMachine: StateMachineService,
    @Inject(CACHE_MANAGER) private cacheManager: Cache,
    @Inject(WINSTON_MODULE_NEST_PROVIDER)
    private readonly logger: LoggerService,
  ) {}

  async initiatePayment(createPaymentDto: CreatePaymentDto): Promise<PaymentResponseDto> {
    const reference = uuidv4();

    this.logger.log(`Initiating payment with reference: ${reference}`);

    const payment = this.paymentRepository.create({
      ...createPaymentDto,
      reference,
      status: PaymentStatus.INITIATED,
    });

    const savedPayment = await this.paymentRepository.save(payment);

    this.logger.log(`Payment initiated successfully: ${reference}`);

    return this.toPaymentResponse(savedPayment);
  }

  async getPaymentByReference(reference: string): Promise<PaymentResponseDto> {
    this.logger.log(`Fetching payment with reference: ${reference}`);

    const payment = await this.paymentRepository.findOne({
      where: { reference },
    });

    if (!payment) {
      this.logger.warn(`Payment not found: ${reference}`);
      throw new NotFoundException(`Payment with reference ${reference} not found`);
    }

    return this.toPaymentResponse(payment);
  }

  async updatePaymentStatus(
    reference: string,
    updateStatusDto: UpdateStatusDto,
  ): Promise<PaymentResponseDto> {
    const { status, provider_transaction_id } = updateStatusDto;

    this.logger.log(`Updating payment ${reference} to status: ${status}`);

    const payment = await this.paymentRepository.findOne({
      where: { reference },
    });

    if (!payment) {
      this.logger.warn(`Payment not found: ${reference}`);
      throw new NotFoundException(`Payment with reference ${reference} not found`);
    }

    // Validate state transition
    this.stateMachine.validateTransition(payment.status, status);

    // Update payment
    payment.status = status;
    if (provider_transaction_id) {
      payment.provider_transaction_id = provider_transaction_id;
    }

    const updatedPayment = await this.paymentRepository.save(payment);

    this.logger.log(`Payment ${reference} updated to ${status}`);

    return this.toPaymentResponse(updatedPayment);
  }

  async processWebhook(webhookDto: WebhookDto): Promise<WebhookResponseDto> {
    const { payment_reference, status, provider_transaction_id, timestamp } = webhookDto;

    this.logger.log(`Processing webhook for payment: ${payment_reference}`);

    // Check idempotency
    const idempotencyKey = `webhook:${payment_reference}:${provider_transaction_id}`;
    const alreadyProcessed = await this.cacheManager.get(idempotencyKey);

    if (alreadyProcessed) {
      this.logger.log(`Webhook already processed (idempotent): ${idempotencyKey}`);
      return {
        success: true,
        message: 'Webhook already processed',
        payment_reference,
      };
    }

    // Find payment
    const payment = await this.paymentRepository.findOne({
      where: { reference: payment_reference },
    });

    if (!payment) {
      this.logger.warn(`Payment not found for webhook: ${payment_reference}`);
      throw new NotFoundException(`Payment with reference ${payment_reference} not found`);
    }

    // Validate state transition
    try {
      this.stateMachine.validateTransition(payment.status, status);
    } catch (error) {
      // If already in terminal state and webhook status matches, it's idempotent
      if (payment.status === status && this.stateMachine.isTerminalState(status)) {
        this.logger.log(`Payment already in terminal state: ${status}`);
        // Store idempotency key
        await this.cacheManager.set(idempotencyKey, true, 86400000); // 24 hours
        return {
          success: true,
          message: 'Payment already in requested state',
          payment_reference,
        };
      }
      throw error;
    }

    // Update payment
    payment.status = status;
    payment.provider_transaction_id = provider_transaction_id;
    await this.paymentRepository.save(payment);

    // Store idempotency key (24 hours)
    await this.cacheManager.set(idempotencyKey, true, 86400000);

    this.logger.log(`Webhook processed successfully for payment: ${payment_reference}`);

    return {
      success: true,
      message: 'Webhook processed successfully',
      payment_reference,
    };
  }

  private toPaymentResponse(payment: Payment): PaymentResponseDto {
    return {
      id: payment.id,
      reference: payment.reference,
      amount: Number(payment.amount),
      currency: payment.currency,
      payment_method: payment.payment_method,
      customer_phone: payment.customer_phone,
      customer_email: payment.customer_email,
      status: payment.status,
      provider_transaction_id: payment.provider_transaction_id,
      created_at: payment.created_at,
      updated_at: payment.updated_at,
    };
  }
}