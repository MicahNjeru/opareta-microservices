import { Test, TestingModule } from '@nestjs/testing';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { Currency, PaymentMethod, PaymentStatus } from './entities/payment.entity';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { WINSTON_MODULE_NEST_PROVIDER } from 'nest-winston';
import { AuthGuard } from '../auth/guards/auth.guard';

describe('PaymentsController', () => {
  let controller: PaymentsController;
  let paymentsService: PaymentsService;

  const mockPaymentsService = {
    initiatePayment: jest.fn(),
    getPaymentByReference: jest.fn(),
    updatePaymentStatus: jest.fn(),
    processWebhook: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [PaymentsController],
      providers: [
        {
          provide: PaymentsService,
          useValue: mockPaymentsService,
        },
        // Mock dependencies required by AuthGuard
        {
          provide: CACHE_MANAGER,
          useValue: { get: jest.fn(), set: jest.fn() },
        },
        {
          provide: ConfigService,
          useValue: { get: jest.fn() },
        },
        {
          provide: HttpService,
          useValue: { get: jest.fn(), post: jest.fn() },
        },
        {
          provide: WINSTON_MODULE_NEST_PROVIDER,
          useValue: { log: jest.fn(), error: jest.fn(), warn: jest.fn() },
        },
        {
          provide: AuthGuard,
          useValue: { canActivate: jest.fn().mockReturnValue(true) },
        },
      ],
    }).compile();

    controller = module.get<PaymentsController>(PaymentsController);
    paymentsService = module.get<PaymentsService>(PaymentsService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('initiatePayment', () => {
    it('should call paymentsService.initiatePayment and return result', async () => {
      const createDto = {
        amount: 10000,
        currency: Currency.KES,
        payment_method: PaymentMethod.MOBILE_MONEY,
        customer_phone: '+254700000000',
        customer_email: 'test@example.com',
      };

      const mockResult = {
        id: '123',
        reference: 'ref-123',
        ...createDto,
        status: PaymentStatus.INITIATED,
        created_at: new Date(),
        updated_at: new Date(),
      };

      mockPaymentsService.initiatePayment.mockResolvedValue(mockResult);

      const result = await controller.initiatePayment(createDto);

      expect(result).toEqual(mockResult);
      expect(paymentsService.initiatePayment).toHaveBeenCalledWith(createDto);
    });
  });

  describe('getPayment', () => {
    it('should call paymentsService.getPaymentByReference', async () => {
      const mockResult = {
        id: '123',
        reference: 'ref-123',
        amount: 10000,
        currency: Currency.KES,
        payment_method: PaymentMethod.MOBILE_MONEY,
        customer_phone: '+254700000000',
        customer_email: 'test@example.com',
        status: PaymentStatus.INITIATED,
        created_at: new Date(),
        updated_at: new Date(),
      };

      mockPaymentsService.getPaymentByReference.mockResolvedValue(mockResult);

      const result = await controller.getPayment('ref-123');

      expect(result).toEqual(mockResult);
      expect(paymentsService.getPaymentByReference).toHaveBeenCalledWith(
        'ref-123',
      );
    });
  });

  describe('updatePaymentStatus', () => {
    it('should call paymentsService.updatePaymentStatus', async () => {
      const updateDto = {
        status: PaymentStatus.PENDING,
        provider_transaction_id: 'TXN123',
      };

      const mockResult = {
        id: '123',
        reference: 'ref-123',
        amount: 10000,
        currency: Currency.KES,
        payment_method: PaymentMethod.MOBILE_MONEY,
        customer_phone: '+254700000000',
        customer_email: 'test@example.com',
        status: PaymentStatus.PENDING,
        provider_transaction_id: 'TXN123',
        created_at: new Date(),
        updated_at: new Date(),
      };

      mockPaymentsService.updatePaymentStatus.mockResolvedValue(mockResult);

      const result = await controller.updatePaymentStatus('ref-123', updateDto);

      expect(result).toEqual(mockResult);
      expect(paymentsService.updatePaymentStatus).toHaveBeenCalledWith(
        'ref-123',
        updateDto,
      );
    });
  });

  describe('processWebhook', () => {
    it('should call paymentsService.processWebhook', async () => {
      const webhookDto = {
        payment_reference: 'ref-123',
        status: PaymentStatus.SUCCESS,
        provider_transaction_id: 'TXN123',
        timestamp: new Date().toISOString(),
      };

      const mockResult = {
        success: true,
        message: 'Webhook processed successfully',
        payment_reference: 'ref-123',
      };

      mockPaymentsService.processWebhook.mockResolvedValue(mockResult);

      const result = await controller.processWebhook(webhookDto);

      expect(result).toEqual(mockResult);
      expect(paymentsService.processWebhook).toHaveBeenCalledWith(webhookDto);
    });
  });

  describe('getHealth', () => {
    it('should return health status', () => {
      const result = controller.getHealth();

      expect(result).toHaveProperty('status', 'ok');
      expect(result).toHaveProperty('service', 'payment-service');
      expect(result).toHaveProperty('timestamp');
    });
  });
});