import { Test, TestingModule } from '@nestjs/testing';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

describe('AuthController', () => {
  let controller: AuthController;
  let authService: AuthService;

  const mockAuthService = {
    register: jest.fn(),
    login: jest.fn(),
    validateToken: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [AuthController],
      providers: [
        {
          provide: AuthService,
          useValue: mockAuthService,
        },
      ],
    }).compile();

    controller = module.get<AuthController>(AuthController);
    authService = module.get<AuthService>(AuthService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('register', () => {
    it('should call authService.register and return result', async () => {
      const registerDto = {
        phone_number: '+256700000000',
        email: 'test@example.com',
        password: 'Test@1234',
      };

      const mockResult = {
        id: '123',
        phone_number: registerDto.phone_number,
        email: registerDto.email,
        created_at: new Date(),
      };

      mockAuthService.register.mockResolvedValue(mockResult);

      const result = await controller.register(registerDto);

      expect(result).toEqual(mockResult);
      expect(authService.register).toHaveBeenCalledWith(registerDto);
    });
  });

  describe('login', () => {
    it('should call authService.login and return token', async () => {
      const loginDto = {
        phone_number: '+256700000000',
        password: 'Test@1234',
      };

      const mockResult = {
        access_token: 'mock-token',
        user: {
          id: '123',
          phone_number: loginDto.phone_number,
          email: 'test@example.com',
          created_at: new Date(),
        },
      };

      mockAuthService.login.mockResolvedValue(mockResult);

      const result = await controller.login(loginDto);

      expect(result).toEqual(mockResult);
      expect(authService.login).toHaveBeenCalledWith(loginDto);
    });
  });

  describe('validateToken', () => {
    it('should call authService.validateToken and return result', async () => {
      const validateTokenDto = {
        token: 'valid-token',
      };

      const mockResult = {
        valid: true,
        user: {
          id: '123',
          phone_number: '+256700000000',
          email: 'test@example.com',
          created_at: new Date(),
        },
      };

      mockAuthService.validateToken.mockResolvedValue(mockResult);

      const result = await controller.validateToken(validateTokenDto);

      expect(result).toEqual(mockResult);
      expect(authService.validateToken).toHaveBeenCalledWith(validateTokenDto);
    });
  });

  describe('getHealth', () => {
    it('should return health status', () => {
      const result = controller.getHealth();

      expect(result).toHaveProperty('status', 'ok');
      expect(result).toHaveProperty('service', 'auth-service');
      expect(result).toHaveProperty('timestamp');
    });
  });
});