import { Test, TestingModule } from '@nestjs/testing';
import { NotFoundException, BadRequestException } from '@nestjs/common';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { WINSTON_MODULE_NEST_PROVIDER } from 'nest-winston';
import { PaymentsService } from './payments.service';
import { Payment, PaymentStatus, Currency, PaymentMethod } from './entities/payment.entity';
import { StateMachineService } from './services/state-machine.service';

describe('PaymentsService', () => {
  let service: PaymentsService;
  let paymentRepository: Repository<Payment>;
  let cacheManager: any;
  let stateMachine: StateMachineService;

  const mockPaymentRepository = {
    create: jest.fn(),
    save: jest.fn(),
    findOne: jest.fn(),
  };

  const mockCacheManager = {
    get: jest.fn(),
    set: jest.fn(),
  };

  const mockLogger = {
    log: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PaymentsService,
        StateMachineService,
        {
          provide: getRepositoryToken(Payment),
          useValue: mockPaymentRepository,
        },
        {
          provide: CACHE_MANAGER,
          useValue: mockCacheManager,
        },
        {
          provide: WINSTON_MODULE_NEST_PROVIDER,
          useValue: mockLogger,
        },
      ],
    }).compile();

    service = module.get<PaymentsService>(PaymentsService);
    paymentRepository = module.get<Repository<Payment>>(getRepositoryToken(Payment));
    cacheManager = module.get(CACHE_MANAGER);
    stateMachine = module.get<StateMachineService>(StateMachineService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('initiatePayment', () => {
    it('should create a new payment with INITIATED status', async () => {
      const createDto = {
        amount: 10000,
        currency: Currency.KES,
        payment_method: PaymentMethod.MOBILE_MONEY,
        customer_phone: '+254700000000',
        customer_email: 'test@example.com',
      };

      const mockPayment = {
        id: '123',
        reference: 'ref-123',
        ...createDto,
        status: PaymentStatus.INITIATED,
        created_at: new Date(),
        updated_at: new Date(),
      };

      mockPaymentRepository.create.mockReturnValue(mockPayment);
      mockPaymentRepository.save.mockResolvedValue(mockPayment);

      const result = await service.initiatePayment(createDto);

      expect(result.status).toBe(PaymentStatus.INITIATED);
      expect(result.reference).toBeDefined();
      expect(mockPaymentRepository.save).toHaveBeenCalled();
    });
  });

  describe('getPaymentByReference', () => {
    it('should return payment if found', async () => {
      const mockPayment = {
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

      mockPaymentRepository.findOne.mockResolvedValue(mockPayment);

      const result = await service.getPaymentByReference('ref-123');

      expect(result.reference).toBe('ref-123');
    });

    it('should throw NotFoundException if payment not found', async () => {
      mockPaymentRepository.findOne.mockResolvedValue(null);

      await expect(service.getPaymentByReference('ref-999')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('updatePaymentStatus', () => {
    it('should update status with valid transition', async () => {
      const mockPayment = {
        id: '123',
        reference: 'ref-123',
        status: PaymentStatus.INITIATED,
        amount: 10000,
      };

      const updateDto = {
        status: PaymentStatus.PENDING,
        provider_transaction_id: 'TXN123',
      };

      mockPaymentRepository.findOne.mockResolvedValue(mockPayment);
      mockPaymentRepository.save.mockResolvedValue({
        ...mockPayment,
        ...updateDto,
      });

      const result = await service.updatePaymentStatus('ref-123', updateDto);

      expect(result.status).toBe(PaymentStatus.PENDING);
      expect(result.provider_transaction_id).toBe('TXN123');
    });

    it('should throw BadRequestException for invalid transition', async () => {
      const mockPayment = {
        id: '123',
        reference: 'ref-123',
        status: PaymentStatus.INITIATED,
      };

      mockPaymentRepository.findOne.mockResolvedValue(mockPayment);

      await expect(
        service.updatePaymentStatus('ref-123', {
          status: PaymentStatus.SUCCESS,
        }),
      ).rejects.toThrow(BadRequestException);
    });
  });

  describe('processWebhook', () => {
    it('should process webhook successfully', async () => {
      const webhookDto = {
        payment_reference: 'ref-123',
        status: PaymentStatus.SUCCESS,
        provider_transaction_id: 'TXN123',
        timestamp: new Date().toISOString(),
      };

      const mockPayment = {
        id: '123',
        reference: 'ref-123',
        status: PaymentStatus.PENDING,
      };

      mockCacheManager.get.mockResolvedValue(null);
      mockPaymentRepository.findOne.mockResolvedValue(mockPayment);
      mockPaymentRepository.save.mockResolvedValue({
        ...mockPayment,
        status: webhookDto.status,
        provider_transaction_id: webhookDto.provider_transaction_id,
      });

      const result = await service.processWebhook(webhookDto);

      expect(result.success).toBe(true);
      expect(mockCacheManager.set).toHaveBeenCalled();
    });

    it('should handle idempotent webhooks', async () => {
      const webhookDto = {
        payment_reference: 'ref-123',
        status: PaymentStatus.SUCCESS,
        provider_transaction_id: 'TXN123',
        timestamp: new Date().toISOString(),
      };

      mockCacheManager.get.mockResolvedValue(true);

      const result = await service.processWebhook(webhookDto);

      expect(result.success).toBe(true);
      expect(result.message).toContain('already processed');
      expect(mockPaymentRepository.save).not.toHaveBeenCalled();
    });
  });
});