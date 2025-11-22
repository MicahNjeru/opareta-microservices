import { Test, TestingModule } from '@nestjs/testing';
import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { User } from './entities/user.entity';
import { WINSTON_MODULE_NEST_PROVIDER } from 'nest-winston';

describe('AuthService', () => {
  let service: AuthService;
  let userRepository: Repository<User>;
  let jwtService: JwtService;

  const mockUserRepository = {
    findOne: jest.fn(),
    create: jest.fn(),
    save: jest.fn(),
  };

  const mockJwtService = {
    signAsync: jest.fn(),
    verifyAsync: jest.fn(),
  };

  const mockLogger = {
    log: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: getRepositoryToken(User),
          useValue: mockUserRepository,
        },
        {
          provide: JwtService,
          useValue: mockJwtService,
        },
        {
          provide: WINSTON_MODULE_NEST_PROVIDER,
          useValue: mockLogger,
        },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
    userRepository = module.get<Repository<User>>(getRepositoryToken(User));
    jwtService = module.get<JwtService>(JwtService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('register', () => {
    const registerDto = {
      phone_number: '+254700000000',
      email: 'test@example.com',
      password: 'Test@1234',
    };

    it('should successfully register a new user', async () => {
      const mockUser = {
        id: '123',
        phone_number: registerDto.phone_number,
        email: registerDto.email,
        password_hash: 'hashedPassword',
        created_at: new Date(),
        updated_at: new Date(),
      };

      mockUserRepository.findOne.mockResolvedValue(null);
      mockUserRepository.create.mockReturnValue(mockUser);
      mockUserRepository.save.mockResolvedValue(mockUser);

      const result = await service.register(registerDto);

      expect(result).toEqual({
        id: mockUser.id,
        phone_number: mockUser.phone_number,
        email: mockUser.email,
        created_at: mockUser.created_at,
      });
      expect(mockUserRepository.findOne).toHaveBeenCalled();
      expect(mockUserRepository.save).toHaveBeenCalled();
    });

    it('should throw ConflictException if phone number already exists', async () => {
      mockUserRepository.findOne.mockResolvedValue({
        phone_number: registerDto.phone_number,
      });

      await expect(service.register(registerDto)).rejects.toThrow(
        ConflictException,
      );
    });

    it('should throw ConflictException if email already exists', async () => {
      mockUserRepository.findOne.mockResolvedValue({
        email: registerDto.email,
      });

      await expect(service.register(registerDto)).rejects.toThrow(
        ConflictException,
      );
    });
  });

  describe('login', () => {
    const loginDto = {
      phone_number: '+254700000000',
      password: 'Test@1234',
    };

    it('should successfully login and return token', async () => {
      const mockUser = {
        id: '123',
        phone_number: loginDto.phone_number,
        email: 'test@example.com',
        password_hash: await bcrypt.hash(loginDto.password, 10),
        created_at: new Date(),
        updated_at: new Date(),
      };

      mockUserRepository.findOne.mockResolvedValue(mockUser);
      mockJwtService.signAsync.mockResolvedValue('mock-jwt-token');

      const result = await service.login(loginDto);

      expect(result).toHaveProperty('access_token', 'mock-jwt-token');
      expect(result).toHaveProperty('user');
      expect(result.user.id).toBe(mockUser.id);
    });

    it('should throw UnauthorizedException if user not found', async () => {
      mockUserRepository.findOne.mockResolvedValue(null);

      await expect(service.login(loginDto)).rejects.toThrow(
        UnauthorizedException,
      );
    });

    it('should throw UnauthorizedException if password is incorrect', async () => {
      const mockUser = {
        id: '123',
        phone_number: loginDto.phone_number,
        password_hash: await bcrypt.hash('DifferentPassword', 10),
      };

      mockUserRepository.findOne.mockResolvedValue(mockUser);

      await expect(service.login(loginDto)).rejects.toThrow(
        UnauthorizedException,
      );
    });
  });

  describe('validateToken', () => {
    it('should return valid:true for valid token', async () => {
      const mockPayload = {
        sub: '123',
        phone_number: '+254700000000',
        email: 'test@example.com',
      };

      const mockUser = {
        id: '123',
        phone_number: '+254700000000',
        email: 'test@example.com',
        created_at: new Date(),
        updated_at: new Date(),
      };

      mockJwtService.verifyAsync.mockResolvedValue(mockPayload);
      mockUserRepository.findOne.mockResolvedValue(mockUser);

      const result = await service.validateToken({ token: 'valid-token' });

      expect(result.valid).toBe(true);
      expect(result.user).toBeDefined();
    });

    it('should return valid:false for invalid token', async () => {
      mockJwtService.verifyAsync.mockRejectedValue(new Error('Invalid token'));

      const result = await service.validateToken({ token: 'invalid-token' });

      expect(result.valid).toBe(false);
      expect(result.message).toBeDefined();
    });

    it('should return valid:false if user not found', async () => {
      mockJwtService.verifyAsync.mockResolvedValue({ sub: '123' });
      mockUserRepository.findOne.mockResolvedValue(null);

      const result = await service.validateToken({ token: 'valid-token' });

      expect(result.valid).toBe(false);
      expect(result.message).toBe('User not found');
    });
  });
});