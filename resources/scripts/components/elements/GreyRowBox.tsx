import styled from 'styled-components/macro';
import tw from 'twin.macro';

export default styled.div<{ $hoverable?: boolean }>`
    ${tw`flex rounded-xl no-underline text-neutral-200 items-center p-4 transition-all duration-200 overflow-hidden`};
    background: linear-gradient(145deg, rgba(10,17,28,.96), rgba(7,13,21,.88));
    border: 1px solid rgba(255,255,255,.08);
    box-shadow: 0 14px 38px rgba(0,0,0,.2);

    ${(props) => props.$hoverable !== false && `
        &:hover {
            border-color: rgba(8,168,255,.28);
            transform: translateY(-2px);
            box-shadow: 0 20px 50px rgba(0,0,0,.28);
            background: linear-gradient(145deg, rgba(14,25,39,.98), rgba(8,16,27,.94));
        }
    `};

    & .icon {
        ${tw`rounded-xl w-14 h-14 flex items-center justify-center p-3`};
        background: rgba(8,168,255,.09);
        color: #08A8FF;
        border: 1px solid rgba(8,168,255,.14);
    }
`;
